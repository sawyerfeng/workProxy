import AppKit
import SwiftUI
import XCTest
import WorkProxyCore
@testable import WorkProxy

final class AppearanceTests: XCTestCase {
    func testLegacySettingsFollowSystemAndModesRoundTrip() throws {
        let encoder = JSONEncoder()
        let old = try encoder.encode(AppSettings.default)
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: old).appearance)
        XCTAssertNil(AppearanceMode.automatic.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
        for mode in AppearanceMode.allCases {
            var settings = AppSettings.default
            settings.appearance = mode
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoder.encode(settings)), settings)
        }
    }

    @MainActor
    func testAppearancePersistsWithoutChangingRules() {
        let initial = AppSettings(rules: [Rule(name: "Office", network: .wifi(ssid: "Office"), action: .off)])
        let store = InMemorySettingsStore(initial)
        let model = AppModel(store: store)
        for mode in AppearanceMode.allCases {
            model.setAppearance(mode)
            XCTAssertEqual(model.settings.appearance, mode)
            XCTAssertEqual(model.settings.rules, initial.rules)
            XCTAssertEqual(AppModel(store: store).settings.appearance, mode)
        }
    }

    @MainActor
    func testLongNetworkNameExpandsRowAtMinimumWindowWidth() {
        let model = AppModel(store: InMemorySettingsStore())
        func height(_ label: String) -> CGFloat {
            let rule = Rule(name: "旧规则名称", network: .wifi(ssid: label), action: .off)
            let view = NSHostingView(rootView: RuleRow(model: model, rule: rule, priority: 1).frame(width: 460))
            return view.fittingSize.height
        }
        XCTAssertGreaterThan(height(String(repeating: "较长的无线网络名称", count: 5)), height("Office"))
    }

    @MainActor
    func testNetworkTitleIgnoresLegacyRuleName() {
        let model = AppModel(store: InMemorySettingsStore())
        let rule = Rule(name: "这个旧规则名不再显示", network: .wifi(ssid: "Office"), action: .off)
        XCTAssertEqual(model.networkName(for: rule.network), "Office")
        XCTAssertEqual(model.networkName(for: .wired(interfaceName: "en7")), "en7")
    }
}
