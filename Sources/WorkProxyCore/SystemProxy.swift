import Darwin
import Foundation

/// 代理端点。工具默认使用本机客户端的混合端口。
public struct ProxyEndpoint: Equatable, Codable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String = "127.0.0.1", port: Int = 7897) {
        self.host = host
        self.port = port
    }

    public var display: String { "\(host):\(port)" }
}

public struct NetworkService: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var device: String?
    public var enabled: Bool

    public init(name: String, device: String? = nil, enabled: Bool = true) {
        self.name = name
        self.device = device
        self.enabled = enabled
    }
}

/// 一个网络服务上的系统代理开关。PAC 与自动发现只读取，不修改。
public struct SystemProxySwitches: Equatable, Codable, Sendable {
    public var http: Bool
    public var https: Bool
    public var socks: Bool
    public var pac: Bool
    public var autoDiscovery: Bool

    public init(http: Bool = false, https: Bool = false, socks: Bool = false,
                pac: Bool = false, autoDiscovery: Bool = false) {
        self.http = http
        self.https = https
        self.socks = socks
        self.pac = pac
        self.autoDiscovery = autoDiscovery
    }

    /// 三个显式代理全部开启即视为“系统代理已开”。PAC 是另一种模式，不算在内。
    public var isOn: Bool { http && https && socks }

    /// 三个显式代理与 PAC/自动发现全部关闭才算“系统代理已关”。
    public var isOff: Bool { !http && !https && !socks && !pac && !autoDiscovery }

    public var isMixed: Bool { !isOn && !isOff }
}

public enum SystemProxyError: Error, LocalizedError, Sendable {
    case commandFailed(command: String, status: Int32, message: String)
    case unparsable(command: String, output: String)
    case endpointUnreachable(host: String, port: Int)
    case noServices
    case verificationFailed(service: String, expected: Bool, actual: SystemProxySwitches)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, message):
            return "命令失败（\(status)）：\(command)\(message.isEmpty ? "" : " — \(message)")"
        case let .unparsable(command, output):
            return "无法解析 \(command) 的输出：\(output)"
        case let .endpointUnreachable(host, port):
            return "代理端口 \(host):\(port) 无法连接，未修改系统代理。请先启动客户端内核。"
        case .noServices:
            return "没有可用的网络服务。"
        case let .verificationFailed(service, expected, actual):
            return "写入后回读不一致：\(service) 期望\(expected ? "开启" : "关闭")，实际 HTTP=\(actual.http) HTTPS=\(actual.https) SOCKS=\(actual.socks) PAC=\(actual.pac) 自动发现=\(actual.autoDiscovery)。"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemProxyError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                message: message
            )
        }
        return out
    }
}

/// 对 `/usr/sbin/networksetup` 的薄封装。只操作显式代理，不碰 PAC、DNS 或服务顺序。
public struct Networksetup: Sendable {
    public static let executable = "/usr/sbin/networksetup"
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func services() throws -> [NetworkService] {
        let devices = try serviceDevices()
        let output = try runner.run(Self.executable, ["-listallnetworkservices"])
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("An asterisk")
                    && !line.hasPrefix("** Error")
            }
            .map { line in
                let enabled = !line.hasPrefix("*")
                let name = enabled ? line : String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                return NetworkService(name: name, device: devices[name], enabled: enabled)
            }
    }

    /// 把主接口（如 en7）映射到当前 Location 中的服务名。
    public func serviceName(forDevice device: String) throws -> String? {
        try services().first { $0.device == device }?.name
    }

    /// 读取系统保存过的 Wi-Fi 网络（曾经连接或手动加入过的）。
    /// 参数是 Wi-Fi 的硬件接口名，例如 en0。
    public func preferredWirelessNetworks(interfaceName: String) throws -> [String] {
        let output = try runner.run(Self.executable,
                                    ["-listpreferredwirelessnetworks", interfaceName])
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("Preferred networks")
                    && !line.hasPrefix("** Error")
            }
    }

    /// 读取当前已连接的 Wi-Fi 名称；未连接或不可读时返回 nil。
    public func currentWirelessNetwork(interfaceName: String) throws -> String? {
        let output = try runner.run(Self.executable, ["-getairportnetwork", interfaceName])
        for line in output.split(separator: "\n") {
            for prefix in ["Current Wi-Fi Network:", "Current AirPort Network:"] {
                if let range = line.range(of: prefix) {
                    let ssid = line[range.upperBound...]
                        .trimmingCharacters(in: .whitespaces)
                    return ssid.isEmpty ? nil : ssid
                }
            }
        }
        return nil
    }

    public func read(_ service: String) throws -> SystemProxySwitches {
        let web = try runner.run(Self.executable, ["-getwebproxy", service])
        let secure = try runner.run(Self.executable, ["-getsecurewebproxy", service])
        let socks = try runner.run(Self.executable, ["-getsocksfirewallproxy", service])
        let pac = try runner.run(Self.executable, ["-getautoproxyurl", service])
        let discovery = try runner.run(Self.executable, ["-getproxyautodiscovery", service])
        return SystemProxySwitches(
            http: try enabledFlag(web, command: "-getwebproxy"),
            https: try enabledFlag(secure, command: "-getsecurewebproxy"),
            socks: try enabledFlag(socks, command: "-getsocksfirewallproxy"),
            pac: try enabledFlag(pac, command: "-getautoproxyurl"),
            autoDiscovery: discovery.lowercased().contains("auto proxy discovery: on")
        )
    }

    /// 三个 `-set...proxy` 命令都会同时写入地址端口并开启代理。
    public func enable(_ service: String, endpoint: ProxyEndpoint) throws {
        for flag in ["-setwebproxy", "-setsecurewebproxy", "-setsocksfirewallproxy"] {
            _ = try runner.run(Self.executable, [flag, service, endpoint.host, String(endpoint.port)])
        }
    }

    public func disable(_ service: String) throws {
        for flag in ["-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate"] {
            _ = try runner.run(Self.executable, [flag, service, "off"])
        }
    }

    private func serviceDevices() throws -> [String: String] {
        let output = try runner.run(Self.executable, ["-listnetworkserviceorder"])
        var devices: [String: String] = [:]
        var current: String?
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                current = nil
                continue
            }
            if let name = Self.serviceName(fromOrderLine: line) {
                current = name
            } else if let name = current, let range = line.range(of: "Device: ") {
                let device = line[range.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
                if !device.isEmpty {
                    devices[name] = device
                }
            }
        }
        return devices
    }

    /// `-listnetworkserviceorder` 的服务行形如 `(1) Wi-Fi`，设备行以 `(Hardware Port:` 开头。
    private static func serviceName(fromOrderLine line: String) -> String? {
        guard line.hasPrefix("("), line.dropFirst().first?.isNumber == true,
              let close = line.firstIndex(of: ")") else { return nil }
        var name = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("*") {
            name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }

    private func enabledFlag(_ output: String, command: String) throws -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0] == "Enabled" else { continue }
            return parts[1].caseInsensitiveCompare("yes") == .orderedSame
        }
        throw SystemProxyError.unparsable(command: command, output: output)
    }
}

public protocol EndpointProbing: Sendable {
    func isReachable(_ endpoint: ProxyEndpoint, timeout: TimeInterval) -> Bool
}

/// 只做一次 TCP 连接检查，不发送任何请求。
public struct TCPEndpointProbe: EndpointProbing {
    public init() {}

    public func isReachable(_ endpoint: ProxyEndpoint, timeout: TimeInterval = 1.5) -> Bool {
        var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC,
                             ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(endpoint.host, String(endpoint.port), &hints, &addresses) == 0,
              let first = addresses else { return false }
        defer { freeaddrinfo(addresses) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        while let address = current {
            let fd = socket(address.pointee.ai_family, address.pointee.ai_socktype,
                            address.pointee.ai_protocol)
            if fd >= 0 {
                defer { close(fd) }
                if fcntl(fd, F_SETFL, O_NONBLOCK) >= 0 {
                    if connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 {
                        return true
                    }
                    if errno == EINPROGRESS {
                        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        if poll(&descriptor, 1, Int32(timeout * 1000)) > 0 {
                            var error: Int32 = 0
                            var length = socklen_t(MemoryLayout<Int32>.size)
                            if getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0,
                               error == 0 {
                                return true
                            }
                        }
                    }
                }
            }
            current = address.pointee.ai_next
        }
        return false
    }
}

public struct SystemProxyController: Sendable {
    private let setup: Networksetup
    private let probe: any EndpointProbing

    public init(setup: Networksetup = Networksetup(),
                probe: any EndpointProbing = TCPEndpointProbe()) {
        self.setup = setup
        self.probe = probe
    }

    /// 对所有已启用的网络服务统一设置。开启前必须确认端点可连接。
    @discardableResult
    public func apply(_ enabled: Bool, endpoint: ProxyEndpoint,
                      to services: [NetworkService]) throws -> [String: SystemProxySwitches] {
        let targets = services.filter(\.enabled)
        guard !targets.isEmpty else { throw SystemProxyError.noServices }
        if enabled, !probe.isReachable(endpoint, timeout: 1.5) {
            throw SystemProxyError.endpointUnreachable(host: endpoint.host, port: endpoint.port)
        }

        var states: [String: SystemProxySwitches] = [:]
        for service in targets {
            if enabled {
                try setup.enable(service.name, endpoint: endpoint)
            } else {
                try setup.disable(service.name)
            }
            let state = try setup.read(service.name)
            states[service.name] = state
            if enabled ? !state.isOn : !state.isOff {
                throw SystemProxyError.verificationFailed(
                    service: service.name, expected: enabled, actual: state
                )
            }
        }
        return states
    }
}
