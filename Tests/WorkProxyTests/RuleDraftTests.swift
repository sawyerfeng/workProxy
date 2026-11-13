import XCTest
import WorkProxyCore
@testable import WorkProxy

final class RuleDraftTests: XCTestCase {
    func testCurrentWifiNeedsOnlyAction() throws {
        var draft = RuleDraft(rule: nil, currentNetwork:
            NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Office"))
        draft.action = .off
        let rule = try XCTUnwrap(draft.makeRule(id: UUID()))
        XCTAssertEqual(rule.network, .wifi(ssid: "Office"))
        XCTAssertEqual(rule.name, "Wi-Fi：Office")
        XCTAssertEqual(rule.action, .off)
        XCTAssertTrue(rule.enabled)
        XCTAssertNil(rule.place)
    }

    func testMissingNetworkCannotBeSaved() {
        for network in [nil, NetworkIdentity(interfaceName: "en0", kind: .wifi),
                        NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "  \n")] {
            XCTAssertNil(RuleDraft(rule: nil, currentNetwork: network).makeRule(id: UUID()))
        }
    }

    func testWiredNetworkNeedsNoCustomName() throws {
        var draft = RuleDraft(rule: nil, currentNetwork:
            NetworkIdentity(interfaceName: "en7", serviceName: "USB Ethernet", kind: .wired))
        let generated = try XCTUnwrap(draft.makeRule(id: UUID()))
        XCTAssertEqual(generated.network, .wired(interfaceName: "en7"))
        XCTAssertEqual(generated.name, "有线：en7")
        draft.interfaceName = ""
        XCTAssertNil(draft.makeRule(id: UUID()))
    }

    func testEditingPreservesExistingRuleIncludingLocationAndDisabledState() {
        let rule = Rule(name: "原有规则", network: .wifi(ssid: "Office"),
                        place: PlaceCondition(label: "办公室", address: "示例地址",
                                              latitude: 31, longitude: 121, radiusMeters: 300),
                        action: .off, enabled: false)
        let draft = RuleDraft(rule: rule, currentNetwork:
            NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Different"))
        XCTAssertEqual(draft.makeRule(id: rule.id), rule)
    }

    func testLocationMustBeChosenWhenEnabledAndCanBeRemoved() {
        var draft = RuleDraft(rule: nil, currentNetwork:
            NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Office"))
        draft.usePlace = true
        XCTAssertNil(draft.makeRule(id: UUID()))
        draft.hasPlaceCoordinates = true
        XCTAssertNotNil(draft.makeRule(id: UUID())?.place)
        draft.usePlace = false
        XCTAssertNil(draft.makeRule(id: UUID())?.place)
    }
}
