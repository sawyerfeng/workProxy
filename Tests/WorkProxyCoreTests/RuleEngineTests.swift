import XCTest
@testable import WorkProxyCore

final class RuleEngineTests: XCTestCase {
    private let engine = RuleEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let officePlace = PlaceCondition(
        label: "办公室", latitude: 31.2304, longitude: 121.4737, radiusMeters: 100
    )

    private var wifi: NetworkIdentity {
        NetworkIdentity(interfaceName: "en0", serviceName: "Wi-Fi", kind: .wifi, ssid: "Office")
    }

    private var wired: NetworkIdentity {
        NetworkIdentity(interfaceName: "en7", serviceName: "USB LAN", kind: .wired)
    }

    private func fix(latitude: Double = 31.2304, longitude: Double = 121.4737,
                     accuracy: Double = 10, age: TimeInterval = 0) -> LocationFix {
        LocationFix(latitude: latitude, longitude: longitude,
                    horizontalAccuracy: accuracy,
                    timestamp: now.addingTimeInterval(-age))
    }

    func testWifiRuleMatches() {
        let rule = Rule(name: "办公室 Wi-Fi", network: .wifi(ssid: "Office"), action: .on)

        XCTAssertEqual(engine.decide(rules: [rule], identity: wifi, location: nil, now: now),
                       .action(.on, ruleID: rule.id))
    }

    func testWifiRuleDoesNotMatchNilSSID() {
        let rule = Rule(name: "办公室 Wi-Fi", network: .wifi(ssid: "Office"), action: .on)
        let unreadable = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: nil)

        XCTAssertEqual(engine.decide(rules: [rule], identity: unreadable, location: nil, now: now),
                       .none)
    }

    func testWifiRuleDoesNotMatchWired() {
        let rule = Rule(name: "办公室 Wi-Fi", network: .wifi(ssid: "Office"), action: .on)

        XCTAssertEqual(engine.decide(rules: [rule], identity: wired, location: nil, now: now),
                       .none)
    }

    func testWiredInterfaceMatches() {
        let rule = Rule(name: "USB 网卡", network: .wired(interfaceName: "en7"), action: .off)

        XCTAssertEqual(engine.decide(rules: [rule], identity: wired, location: nil, now: now),
                       .action(.off, ruleID: rule.id))
    }

    func testWiredRuleDoesNotMatchOtherInterface() {
        let rule = Rule(name: "USB 网卡", network: .wired(interfaceName: "en9"), action: .off)

        XCTAssertEqual(engine.decide(rules: [rule], identity: wired, location: nil, now: now),
                       .none)
    }

    func testDisabledRuleIsSkipped() {
        let disabled = Rule(name: "停用", network: .wifi(ssid: "Office"),
                            action: .off, enabled: false)
        let enabled = Rule(name: "启用", network: .wifi(ssid: "Office"), action: .on)

        XCTAssertEqual(engine.decide(rules: [disabled, enabled], identity: wifi, location: nil, now: now),
                       .action(.on, ruleID: enabled.id))
    }

    func testRuleOrderWins() {
        let first = Rule(name: "第一条", network: .wifi(ssid: "Office"), action: .off)
        let second = Rule(name: "第二条", network: .wifi(ssid: "Office"), action: .on)

        XCTAssertEqual(engine.decide(rules: [first, second], identity: wifi, location: nil, now: now),
                       .action(.off, ruleID: first.id))
    }

    func testLocationRuleInsideRadiusMatches() {
        let rule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                        place: officePlace, action: .on)

        XCTAssertEqual(engine.decide(rules: [rule], identity: wifi, location: fix(), now: now),
                       .action(.on, ruleID: rule.id))
    }

    func testLocationRuleJustInsideRadiusMatches() {
        let rule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                        place: officePlace, action: .on)

        // 约 89 米，仍在 100 米半径内。
        XCTAssertEqual(engine.decide(rules: [rule], identity: wifi,
                                     location: fix(latitude: 31.2312), now: now),
                       .action(.on, ruleID: rule.id))
    }

    func testLocationRuleOutsideRadiusFallsThroughToNextMatchingRule() {
        let locationRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)
        let fallback = Rule(name: "同名 Wi-Fi 兜底", network: .wifi(ssid: "Office"), action: .off)

        XCTAssertEqual(engine.decide(rules: [locationRule, fallback], identity: wifi,
                                     location: fix(latitude: 31.2404), now: now),
                       .action(.off, ruleID: fallback.id))
        XCTAssertEqual(engine.decide(rules: [locationRule, fallback], identity: wifi,
                                     location: nil, now: now),
                       .action(.off, ruleID: fallback.id))
    }

    func testUnusableLocationSkipsLocationRulesButMatchesLaterUnconditionalRules() {
        let locationRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)
        let fallback = Rule(name: "兜底", network: .wifi(ssid: "Office"), action: .off)
        let unusableFixes = [
            fix(age: 600),              // 过期
            fix(accuracy: -1),          // 负精度
            fix(accuracy: 1_000)        // 精度过低
        ]

        for unusable in unusableFixes {
            XCTAssertEqual(
                engine.decide(rules: [locationRule, fallback], identity: wifi,
                              location: unusable, now: now),
                .action(.off, ruleID: fallback.id),
                "unusable fix should skip the location rule: \(unusable)"
            )
        }
    }

    func testNoMatchingNetworkReturnsNone() {
        let rule = Rule(name: "办公室", network: .wifi(ssid: "Office"), action: .on)
        let other = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Home")

        XCTAssertEqual(engine.decide(rules: [rule], identity: other, location: nil, now: now), .none)
        XCTAssertEqual(engine.decide(rules: [], identity: wifi, location: nil, now: now), .none)
    }

    func testMayRequireLocationTrueWhenFirstMatchingRuleHasPlace() {
        let locationRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)
        let fallback = Rule(name: "兜底", network: .wifi(ssid: "Office"), action: .off)

        XCTAssertTrue(engine.mayRequireLocation(rules: [locationRule, fallback], identity: wifi))
    }

    func testMayRequireLocationFalseWhenFirstMatchingRuleHasNoPlace() {
        let unconditional = Rule(name: "无条件", network: .wifi(ssid: "Office"), action: .off)
        let locationRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)

        XCTAssertFalse(engine.mayRequireLocation(rules: [unconditional, locationRule], identity: wifi))
    }

    func testMayRequireLocationFalseWhenNoNetworkMatches() {
        let locationRule = Rule(name: "办公室", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)

        XCTAssertFalse(engine.mayRequireLocation(rules: [locationRule], identity: wired))
        XCTAssertFalse(engine.mayRequireLocation(rules: [], identity: wifi))
    }

    func testMayRequireLocationIgnoresDisabledRules() {
        let disabledLocation = Rule(name: "停用地点", network: .wifi(ssid: "Office"),
                                    place: officePlace, action: .on, enabled: false)
        let unconditional = Rule(name: "无条件", network: .wifi(ssid: "Office"), action: .off)

        XCTAssertFalse(engine.mayRequireLocation(rules: [disabledLocation, unconditional],
                                                 identity: wifi))
    }

    func testInsertByPriorityPlacesLocationRuleBeforeNormalRuleOfSameNetwork() {
        let normalWifi = Rule(name: "普通 Wi-Fi", network: .wifi(ssid: "Office"), action: .off)
        let normalWired = Rule(name: "普通有线", network: .wired(interfaceName: "en7"), action: .on)
        let locationWifi = Rule(name: "地点 Wi-Fi", network: .wifi(ssid: "Office"),
                                place: officePlace, action: .on)
        var rules = [normalWifi, normalWired]

        rules.insertByPriority(locationWifi)

        XCTAssertEqual(rules.map(\.id), [locationWifi.id, normalWifi.id, normalWired.id])
    }

    func testInsertByPriorityAppendsWhenNoNormalRuleOfSameNetwork() {
        let normalWifi = Rule(name: "普通 Wi-Fi", network: .wifi(ssid: "Office"), action: .off)
        let locationWired = Rule(name: "地点有线", network: .wired(interfaceName: "en7"),
                                 place: officePlace, action: .on)
        let locationOtherWifi = Rule(name: "另一 Wi-Fi", network: .wifi(ssid: "Home"),
                                     place: officePlace, action: .on)
        var rules = [normalWifi]

        rules.insertByPriority(locationWired)
        rules.insertByPriority(locationOtherWifi)

        XCTAssertEqual(rules.map(\.id), [normalWifi.id, locationWired.id, locationOtherWifi.id])
    }
}
