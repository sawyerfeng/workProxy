import Foundation
import SystemConfiguration
import WorkProxyCore

struct EffectiveProxy: Codable {
    let http: Bool
    let https: Bool
    let socks: Bool
    let pac: Bool
    let autoDiscovery: Bool
    let server: String?
    let port: Int?
}

struct ServiceReport: Codable {
    let name: String
    let device: String?
    let enabled: Bool
    let switches: SystemProxySwitches?
    let error: String?
}

struct SystemProxyReport: Codable {
    let capturedAt: Date
    let activeInterface: String?
    let activeService: String?
    let effective: EffectiveProxy?
    let services: [ServiceReport]
    let message: String

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "无法生成报告"
    }
}

enum SystemNetwork {
    static func primaryInterface() -> String? {
        let value = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString)
            as? [String: Any]
        return value?["PrimaryInterface"] as? String
    }

    static func effectiveProxy() -> EffectiveProxy? {
        guard let values = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return nil }
        func flag(_ key: String) -> Bool {
            (values[key] as? NSNumber)?.boolValue ?? false
        }
        return EffectiveProxy(
            http: flag("HTTPEnable"),
            https: flag("HTTPSEnable"),
            socks: flag("SOCKSEnable"),
            pac: flag("ProxyAutoConfigEnable"),
            autoDiscovery: flag("ProxyAutoDiscoveryEnable"),
            server: values["HTTPProxy"] as? String,
            port: (values["HTTPPort"] as? NSNumber)?.intValue
        )
    }
}

struct SystemSnapshot {
    let report: SystemProxyReport
    let states: [String: SystemProxySwitches]
    let services: [NetworkService]

    static func capture(setup: Networksetup, message: String) throws -> SystemSnapshot {
        let activeInterface = SystemNetwork.primaryInterface()
        let services = try setup.services()
        let activeService = activeInterface.flatMap { device in
            services.first { $0.device == device }?.name
        }
        var states: [String: SystemProxySwitches] = [:]
        var errors: [String: String] = [:]
        for service in services where service.enabled {
            do {
                states[service.name] = try setup.read(service.name)
            } catch {
                errors[service.name] = error.localizedDescription
            }
        }
        let report = SystemProxyReport(
            capturedAt: Date(),
            activeInterface: activeInterface,
            activeService: activeService,
            effective: SystemNetwork.effectiveProxy(),
            services: services.map {
                ServiceReport(name: $0.name, device: $0.device, enabled: $0.enabled,
                              switches: states[$0.name], error: errors[$0.name])
            },
            message: message
        )
        return SystemSnapshot(report: report, states: states, services: services)
    }
}
