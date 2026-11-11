import CoreWLAN
import Foundation
import Network
import SystemConfiguration
import WorkProxyCore

/// 读取当前主要物理连接。TUN/utun 不作为网络身份，避免代理自身触发规则。
@MainActor
final class NetworkMonitor {
    private let setup: Networksetup
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.github.sawyerfeng.workproxy.path")
    private var pollTask: Task<Void, Never>?
    private var pathInterfaces: [String] = []
    private var lastIdentity: NetworkIdentity?
    private var serviceCache: [String: String] = [:]
    private var serviceCacheDate = Date.distantPast

    private(set) var currentIdentity: NetworkIdentity?
    var onChange: ((NetworkIdentity?) -> Void)?

    init(setup: Networksetup = Networksetup()) {
        self.setup = setup
    }

    func start() {
        let identity = readIdentity()
        currentIdentity = identity
        lastIdentity = identity

        monitor.pathUpdateHandler = { [weak self] path in
            let names = path.availableInterfaces.map(\.name)
            Task { @MainActor in
                self?.pathInterfaces = names
                self?.refresh()
            }
        }
        monitor.start(queue: queue)

        // NWPathMonitor 不保证在 SSID 变化时回调，补充低频轮询。
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        monitor.cancel()
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        let identity = readIdentity()
        currentIdentity = identity
        guard !same(identity, lastIdentity) else { return }
        lastIdentity = identity
        onChange?(identity)
    }

    private func same(_ lhs: NetworkIdentity?, _ rhs: NetworkIdentity?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return left.isSamePhysicalNetwork(as: right)
        default: return false
        }
    }

    private func readIdentity() -> NetworkIdentity? {
        let primary = Self.primaryInterfaceName()
        guard let interface = Self.physicalInterface(primary: primary,
                                                    candidates: pathInterfaces) else {
            return nil
        }
        refreshServiceCacheIfNeeded()
        if interface == Self.wifiInterfaceName() {
            return NetworkIdentity(interfaceName: interface,
                                   serviceName: serviceCache[interface],
                                   kind: .wifi,
                                   ssid: Self.currentSSID())
        }
        return NetworkIdentity(interfaceName: interface,
                               serviceName: serviceCache[interface],
                               kind: .wired)
    }

    private func refreshServiceCacheIfNeeded() {
        guard Date().timeIntervalSince(serviceCacheDate) > 60 else { return }
        if let services = try? setup.services() {
            var cache: [String: String] = [:]
            for service in services {
                if let device = service.device { cache[device] = service.name }
            }
            serviceCache = cache
        }
        serviceCacheDate = Date()
    }

    private static func physicalInterface(primary: String?, candidates: [String]) -> String? {
        func isVirtual(_ name: String) -> Bool {
            ["utun", "lo", "bridge", "awdl", "llw", "gif", "stf", "anpi"]
                .contains { name.hasPrefix($0) }
        }
        if let primary, !isVirtual(primary) { return primary }
        if let wifi = wifiInterfaceName(), candidates.contains(wifi) { return wifi }
        return candidates.first { !isVirtual($0) }
    }

    private static func primaryInterfaceName() -> String? {
        let value = SCDynamicStoreCopyValue(
            nil, "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any]
        return value?["PrimaryInterface"] as? String
    }

    static func wifiInterfaceName() -> String? {
        CWWiFiClient.shared().interface()?.interfaceName
    }

    private static func currentSSID() -> String? {
        // 未授予定位权限时返回 nil；规则层会跳过 Wi-Fi 名称规则。
        CWWiFiClient.shared().interface()?.ssid()
    }
}
