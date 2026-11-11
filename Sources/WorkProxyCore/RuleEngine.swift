import Foundation

/// 纯规则匹配。按顺序取第一条匹配规则；地点是附加条件，不是独立触发源。
public struct RuleEngine: Sendable {
    public init() {}

    /// 只有当“第一条网络匹配的规则”带地点条件时才需要等待定位。
    /// 如果它前面的同网络规则没有地点条件，定位不会改变结果。
    public func mayRequireLocation(rules: [Rule], identity: NetworkIdentity) -> Bool {
        for rule in rules where rule.enabled && rule.network.matches(identity) {
            return rule.place != nil
        }
        return false
    }

    public func decide(rules: [Rule], identity: NetworkIdentity,
                       location: LocationFix?, now: Date) -> RuleDecision {
        for rule in rules where rule.enabled {
            guard rule.network.matches(identity) else { continue }
            if let place = rule.place {
                guard let location, location.isUsable(at: now),
                      location.distanceMeters(to: place) <= place.radiusMeters else {
                    continue
                }
            }
            return .action(rule.action, ruleID: rule.id)
        }
        return .none
    }
}
