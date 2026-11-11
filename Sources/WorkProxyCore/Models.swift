import Foundation

public enum ProxyAction: String, Codable, CaseIterable, Sendable {
    case on
    case off

    public var displayName: String {
        switch self {
        case .on: return "开启系统代理"
        case .off: return "关闭系统代理"
        }
    }
}

public enum NetworkKind: String, Codable, Sendable {
    case wifi
    case wired
    case other
}

/// 当前主要物理连接的身份。SSID 不可读时为 nil，不能当成空名称规则。
public struct NetworkIdentity: Equatable, Codable, Sendable {
    public var interfaceName: String
    public var serviceName: String?
    public var kind: NetworkKind
    public var ssid: String?

    public init(interfaceName: String, serviceName: String? = nil,
                kind: NetworkKind, ssid: String? = nil) {
        self.interfaceName = interfaceName
        self.serviceName = serviceName
        self.kind = kind
        self.ssid = ssid
    }

    /// 判断是否同一物理网络。服务名与主要接口的展示顺序不参与比较。
    public func isSamePhysicalNetwork(as other: NetworkIdentity) -> Bool {
        interfaceName == other.interfaceName && kind == other.kind && ssid == other.ssid
    }

    public var displayName: String {
        switch kind {
        case .wifi: return ssid ?? serviceName ?? interfaceName
        case .wired: return serviceName ?? interfaceName
        case .other: return serviceName ?? interfaceName
        }
    }
}

public enum RuleNetwork: Codable, Equatable, Sendable {
    case wifi(ssid: String)
    case wired(interfaceName: String)

    public func matches(_ identity: NetworkIdentity) -> Bool {
        switch self {
        case let .wifi(ssid):
            guard identity.kind == .wifi, let current = identity.ssid else { return false }
            return current == ssid
        case let .wired(interfaceName):
            return identity.kind != .wifi && identity.interfaceName == interfaceName
        }
    }

    public var displayName: String {
        switch self {
        case let .wifi(ssid): return "Wi-Fi：\(ssid)"
        case let .wired(interfaceName): return "有线：\(interfaceName)"
        }
    }
}

public struct PlaceCondition: Codable, Equatable, Sendable {
    public var label: String
    public var address: String?
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Double

    public init(label: String, address: String? = nil, latitude: Double,
                longitude: Double, radiusMeters: Double) {
        self.label = label
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}

public struct Rule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var network: RuleNetwork
    public var place: PlaceCondition?
    public var action: ProxyAction
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, network: RuleNetwork,
                place: PlaceCondition? = nil, action: ProxyAction, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.network = network
        self.place = place
        self.action = action
        self.enabled = enabled
    }
}

public extension Array where Element == Rule {
    /// 地点规则默认插在同网络的第一条普通规则之前。
    mutating func insertByPriority(_ rule: Rule) {
        if rule.place != nil,
           let index = firstIndex(where: { $0.network == rule.network && $0.place == nil }) {
            insert(rule, at: index)
        } else {
            append(rule)
        }
    }
}

public struct LocationFix: Equatable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double,
                horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    /// 旧位置或低精度位置按不可用处理。
    public func isUsable(at now: Date, maxAge: TimeInterval = 300,
                         maxAccuracy: Double = 500) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= maxAge
            && horizontalAccuracy > 0 && horizontalAccuracy <= maxAccuracy
    }

    public func distanceMeters(to place: PlaceCondition) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = place.latitude * .pi / 180
        let deltaLat = (place.latitude - latitude) * .pi / 180
        let deltaLon = (place.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

public enum RuleDecision: Equatable, Sendable {
    case action(ProxyAction, ruleID: UUID)
    case none
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var flClash: FlClashSettings?
    public var endpoint: ProxyEndpoint
    public var rules: [Rule]
    public var paused: Bool
    public var launchAtLogin: Bool
    public var hasCompletedOnboarding: Bool

    public init(endpoint: ProxyEndpoint = ProxyEndpoint(),
                rules: [Rule] = [],
                paused: Bool = false,
                launchAtLogin: Bool = true,
                hasCompletedOnboarding: Bool = false) {
        self.endpoint = endpoint
        self.rules = rules
        self.paused = paused
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = AppSettings()
}

public enum LocationUnavailableReason: String, Codable, Sendable {
    case denied
    case timeout
    case lowAccuracy
    case servicesDisabled
    case unknown
}

/// 一次定位请求的结果。失败与超时都返回 `.unavailable`，规则层不区分原因。
public enum LocationResult: Equatable, Sendable {
    case fix(LocationFix)
    case unavailable(LocationUnavailableReason)
}

public struct FlClashSettings: Codable, Equatable, Sendable {
    public var address: String
    public var secret: String

    public init(address: String, secret: String) {
        self.address = address
        self.secret = secret
    }
}
