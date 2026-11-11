import XCTest
@testable import WorkProxyCore

/// 内存中的 networksetup，用来验证命令规划与回读，不触碰真实系统。
private final class FakeSystem: CommandRunning, @unchecked Sendable {
    struct Service {
        var name: String
        var device: String?
        var enabled: Bool
        var http = false
        var https = false
        var socks = false
        var pac = false
        var autoDiscovery = false
        var host = "127.0.0.1"
        var port = 7897
    }

    var services: [Service]
    var calls: [[String]] = []
    var flagsToFail: Set<String> = []
    var servicesIgnoringWrites: Set<String> = []
    var preferredNetworks: [String] = []
    var currentWirelessNetwork: String?

    init(_ services: [Service]) {
        self.services = services
    }

    func run(_ executable: String, _ arguments: [String]) throws -> String {
        calls.append(arguments)
        guard let flag = arguments.first else { return "" }
        if flagsToFail.contains(flag) {
            throw SystemProxyError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                status: 1,
                message: "denied"
            )
        }
        switch flag {
        case "-listnetworkserviceorder":
            var lines = ["An asterisk (*) denotes that a network service is disabled."]
            for (index, service) in services.enumerated() {
                lines.append("(\(index + 1)) \(service.enabled ? "" : "*")\(service.name)")
                lines.append("(Hardware Port: \(service.name), Device: \(service.device ?? ""))")
                lines.append("")
            }
            return lines.joined(separator: "\n")
        case "-listallnetworkservices":
            var lines = ["An asterisk (*) denotes that a network service is disabled."]
            lines += services.map { ($0.enabled ? "" : "*") + $0.name }
            return lines.joined(separator: "\n")
        case "-listpreferredwirelessnetworks":
            var lines = ["Preferred networks on \(arguments[1]):"]
            lines += preferredNetworks.map { "\t\($0)" }
            return lines.joined(separator: "\n")
        case "-getairportnetwork":
            guard let currentWirelessNetwork else {
                return "You are not associated with an AirPort network."
            }
            return "Current Wi-Fi Network: \(currentWirelessNetwork)"
        case "-getwebproxy":
            return proxyOutput("http", service: arguments[1])
        case "-getsecurewebproxy":
            return proxyOutput("https", service: arguments[1])
        case "-getsocksfirewallproxy":
            return proxyOutput("socks", service: arguments[1])
        case "-getautoproxyurl":
            let service = try self.service(arguments[1])
            return "URL: \nEnabled: \(service.pac ? "Yes" : "No")"
        case "-getproxyautodiscovery":
            let service = try self.service(arguments[1])
            return "Auto Proxy Discovery: \(service.autoDiscovery ? "On" : "Off")"
        case "-setwebproxy", "-setsecurewebproxy", "-setsocksfirewallproxy":
            let index = try self.index(arguments[1])
            guard arguments.count == 4, let port = Int(arguments[3]) else {
                throw SystemProxyError.unparsable(command: flag, output: arguments.joined(separator: " "))
            }
            services[index].host = arguments[2]
            services[index].port = port
            guard !servicesIgnoringWrites.contains(services[index].name) else { return "" }
            switch flag {
            case "-setwebproxy": services[index].http = true
            case "-setsecurewebproxy": services[index].https = true
            default: services[index].socks = true
            }
            return ""
        case "-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate":
            let index = try self.index(arguments[1])
            guard arguments.count == 3 else {
                throw SystemProxyError.unparsable(command: flag, output: arguments.joined(separator: " "))
            }
            guard !servicesIgnoringWrites.contains(services[index].name) else { return "" }
            let on = arguments[2] == "on"
            switch flag {
            case "-setwebproxystate": services[index].http = on
            case "-setsecurewebproxystate": services[index].https = on
            default: services[index].socks = on
            }
            return ""
        default:
            return ""
        }
    }

    private func index(_ name: String) throws -> Int {
        guard let index = services.firstIndex(where: { $0.name == name }) else {
            throw SystemProxyError.commandFailed(command: "-service \(name)", status: 1, message: "not found")
        }
        return index
    }

    private func service(_ name: String) throws -> Service {
        services[try index(name)]
    }

    private func proxyOutput(_ key: String, service name: String) -> String {
        guard let service = services.first(where: { $0.name == name }) else { return "** Error" }
        let enabled: Bool
        switch key {
        case "http": enabled = service.http
        case "https": enabled = service.https
        default: enabled = service.socks
        }
        return """
        Enabled: \(enabled ? "Yes" : "No")
        Server: \(service.host)
        Port: \(service.port)
        Authenticated Proxy Enabled: 0
        """
    }
}

private struct FakeProbe: EndpointProbing {
    var reachable: Bool
    func isReachable(_ endpoint: ProxyEndpoint, timeout: TimeInterval) -> Bool { reachable }
}

final class SystemProxyTests: XCTestCase {
    private let endpoint = ProxyEndpoint(host: "127.0.0.1", port: 7897)

    func testParsesServicesDevicesAndDisabledState() throws {
        let system = FakeSystem([
            .init(name: "Wi-Fi", device: "en0", enabled: true),
            .init(name: "USB LAN", device: "en7", enabled: true),
            .init(name: "Thunderbolt Bridge", device: "bridge0", enabled: false)
        ])
        let setup = Networksetup(runner: system)

        let services = try setup.services()

        XCTAssertEqual(services.map(\.name), ["Wi-Fi", "USB LAN", "Thunderbolt Bridge"])
        XCTAssertEqual(services.map(\.device), ["en0", "en7", "bridge0"])
        XCTAssertEqual(services.map(\.enabled), [true, true, false])
        XCTAssertEqual(try setup.serviceName(forDevice: "en7"), "USB LAN")
        XCTAssertNil(try setup.serviceName(forDevice: "en9"))
    }

    func testEnableWritesEndpointAndVerifiesEveryEnabledService() throws {
        let system = FakeSystem([
            .init(name: "Wi-Fi", device: "en0", enabled: true),
            .init(name: "USB LAN", device: "en7", enabled: true),
            .init(name: "Disabled", device: "en9", enabled: false)
        ])
        let controller = SystemProxyController(
            setup: Networksetup(runner: system), probe: FakeProbe(reachable: true)
        )

        let states = try controller.apply(true, endpoint: endpoint, to: try Networksetup(runner: system).services())

        XCTAssertEqual(Set(states.keys), ["Wi-Fi", "USB LAN"])
        XCTAssertTrue(states.values.allSatisfy(\.isOn))
        XCTAssertFalse(system.calls.contains { $0.count > 1 && $0[1] == "Disabled" })
        for service in ["Wi-Fi", "USB LAN"] {
            XCTAssertTrue(system.calls.contains(["-setwebproxy", service, "127.0.0.1", "7897"]))
            XCTAssertTrue(system.calls.contains(["-setsecurewebproxy", service, "127.0.0.1", "7897"]))
            XCTAssertTrue(system.calls.contains(["-setsocksfirewallproxy", service, "127.0.0.1", "7897"]))
        }
    }

    func testDisableTurnsOffEveryEnabledService() throws {
        let system = FakeSystem([
            .init(name: "Wi-Fi", device: "en0", enabled: true, http: true, https: true, socks: true),
            .init(name: "USB LAN", device: "en7", enabled: true, http: true, https: true, socks: true)
        ])
        let setup = Networksetup(runner: system)
        let controller = SystemProxyController(setup: setup, probe: FakeProbe(reachable: false))

        let states = try controller.apply(false, endpoint: endpoint, to: try setup.services())

        XCTAssertEqual(Set(states.keys), ["Wi-Fi", "USB LAN"])
        XCTAssertTrue(states.values.allSatisfy(\.isOff))
        for service in ["Wi-Fi", "USB LAN"] {
            XCTAssertTrue(system.calls.contains(["-setwebproxystate", service, "off"]))
            XCTAssertTrue(system.calls.contains(["-setsecurewebproxystate", service, "off"]))
            XCTAssertTrue(system.calls.contains(["-setsocksfirewallproxystate", service, "off"]))
        }
    }

    func testEnableRefusesToWriteWhenEndpointIsUnreachable() throws {
        let system = FakeSystem([.init(name: "Wi-Fi", device: "en0", enabled: true)])
        let setup = Networksetup(runner: system)
        let controller = SystemProxyController(setup: setup, probe: FakeProbe(reachable: false))

        XCTAssertThrowsError(try controller.apply(true, endpoint: endpoint, to: try setup.services())) { error in
            guard case SystemProxyError.endpointUnreachable = error else {
                return XCTFail("expected endpointUnreachable, got \(error)")
            }
        }
        XCTAssertFalse(system.calls.contains { $0.first?.hasPrefix("-set") == true })
    }

    func testVerificationFailureIsReportedWithActualState() throws {
        let system = FakeSystem([.init(name: "Wi-Fi", device: "en0", enabled: true)])
        system.servicesIgnoringWrites = ["Wi-Fi"]
        let setup = Networksetup(runner: system)
        let controller = SystemProxyController(setup: setup, probe: FakeProbe(reachable: true))

        XCTAssertThrowsError(try controller.apply(true, endpoint: endpoint, to: try setup.services())) { error in
            guard case let SystemProxyError.verificationFailed(service, expected, actual) = error else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
            XCTAssertEqual(service, "Wi-Fi")
            XCTAssertTrue(expected)
            XCTAssertEqual(actual, SystemProxySwitches())
        }
    }

    func testPACOnIsReportedAsNotFullyOffAndBlocksDisableVerification() throws {
        let system = FakeSystem([
            .init(name: "Wi-Fi", device: "en0", enabled: true, pac: true)
        ])
        let setup = Networksetup(runner: system)

        let state = try setup.read("Wi-Fi")

        XCTAssertFalse(state.isOff)
        XCTAssertTrue(state.isMixed)
        XCTAssertThrowsError(try SystemProxyController(setup: setup, probe: FakeProbe(reachable: false))
            .apply(false, endpoint: endpoint, to: try setup.services())) { error in
            guard case SystemProxyError.verificationFailed = error else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
        }
    }

    func testCommandFailureStopsBeforeVerification() throws {
        let system = FakeSystem([.init(name: "Wi-Fi", device: "en0", enabled: true)])
        system.flagsToFail = ["-setsecurewebproxy"]
        let setup = Networksetup(runner: system)
        let controller = SystemProxyController(setup: setup, probe: FakeProbe(reachable: true))

        XCTAssertThrowsError(try controller.apply(true, endpoint: endpoint, to: try setup.services())) { error in
            guard case SystemProxyError.commandFailed = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
        }
    }

    func testPreferredWirelessNetworksSkipsHeaderAndTrimsTabs() throws {
        let system = FakeSystem([])
        system.preferredNetworks = ["Office Wi-Fi", "我家 5G", "Cafe"]
        let setup = Networksetup(runner: system)

        let networks = try setup.preferredWirelessNetworks(interfaceName: "en0")

        XCTAssertEqual(networks, ["Office Wi-Fi", "我家 5G", "Cafe"])
        XCTAssertTrue(system.calls.contains(["-listpreferredwirelessnetworks", "en0"]))
    }

    func testPreferredWirelessNetworksReturnsEmptyListWithoutEntries() throws {
        let setup = Networksetup(runner: FakeSystem([]))

        XCTAssertEqual(try setup.preferredWirelessNetworks(interfaceName: "en0"), [])
    }

    func testPreferredWirelessNetworksIgnoresErrorOutput() throws {
        let system = FakeSystem([])
        system.flagsToFail = ["-listpreferredwirelessnetworks"]
        let setup = Networksetup(runner: system)

        XCTAssertThrowsError(try setup.preferredWirelessNetworks(interfaceName: "en0"))
    }

    func testCurrentWirelessNetworkReadsSSIDAndHandlesDisconnected() throws {
        let system = FakeSystem([])
        let setup = Networksetup(runner: system)

        system.currentWirelessNetwork = "Office Wi-Fi"
        XCTAssertEqual(try setup.currentWirelessNetwork(interfaceName: "en0"), "Office Wi-Fi")

        system.currentWirelessNetwork = nil
        XCTAssertNil(try setup.currentWirelessNetwork(interfaceName: "en0"))
        XCTAssertTrue(system.calls.contains(["-getairportnetwork", "en0"]))
    }

    func testCurrentWirelessNetworkParsesLegacyAirPortLabel() throws {
        let runner = StaticRunner(
            output: "Current AirPort Network: Legacy Network\n"
        )
        let setup = Networksetup(runner: runner)

        XCTAssertEqual(try setup.currentWirelessNetwork(interfaceName: "en1"), "Legacy Network")
    }
}

private struct StaticRunner: CommandRunning {
    var output: String
    func run(_ executable: String, _ arguments: [String]) throws -> String { output }
}
