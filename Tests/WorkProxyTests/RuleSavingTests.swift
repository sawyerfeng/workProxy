import XCTest
import WorkProxyCore
@testable import WorkProxy

private struct FailingStore: SettingsStoring {
    let initial: AppSettings
    func load() throws -> AppSettings { initial }
    func save(_ settings: AppSettings) throws { throw CocoaError(.fileWriteNoPermission) }
}

final class RuleSavingTests: XCTestCase {
    @MainActor
    func testFailedSaveDoesNotAddOrReplaceRuleOrEndpoint() async {
        let existing = Rule(name: "原有规则", network: .wifi(ssid: "Office"), action: .off)
        let initial = AppSettings(rules: [existing], paused: true, launchAtLogin: false)
        let model = AppModel(store: FailingStore(initial: initial))
        XCTAssertFalse(model.addRule(Rule(name: "新规则", network: .wifi(ssid: "Home"), action: .on)))
        XCTAssertEqual(model.settings, initial)
        var edited = existing
        edited.action = .on
        XCTAssertFalse(model.updateRule(edited))
        XCTAssertEqual(model.settings, initial)
        XCTAssertFalse(model.setEndpoint(host: "localhost", portText: "7890"))
        XCTAssertEqual(model.settings, initial)
        XCTAssertNotNil(model.lastError)
    }

    @MainActor
    func testSuccessfulSavePreservesPriorityAndUpdatesSameID() async {
        let existing = Rule(name: "默认", network: .wifi(ssid: "Office"), action: .off)
        let store = InMemorySettingsStore(AppSettings(rules: [existing], paused: true, launchAtLogin: false))
        let model = AppModel(store: store)
        var specific = Rule(name: "地点规则", network: existing.network,
                            place: PlaceCondition(label: "办公室", latitude: 31, longitude: 121, radiusMeters: 500),
                            action: .on)
        XCTAssertTrue(model.addRule(specific))
        XCTAssertEqual(model.settings.rules.map(\.id), [specific.id, existing.id])
        specific.name = "新名称"
        XCTAssertTrue(model.updateRule(specific))
        XCTAssertEqual(model.settings.rules.first, specific)
        XCTAssertEqual(store.savedSettings.last, model.settings)
    }
    @MainActor
    func testQuickSwitchesPersistWithoutChangingRuleOrderOrActions() async {
        let office = Rule(name: "Office", network: .wifi(ssid: "Office"), action: .off)
        let home = Rule(name: "Home", network: .wifi(ssid: "Home"), action: .on)
        let store = InMemorySettingsStore(AppSettings(rules: [office, home], launchAtLogin: false))
        let model = AppModel(store: store)
        model.setRuleEnabled(office.id, false)
        model.setPaused(true)
        XCTAssertEqual(model.settings.rules.map(\.id), [office.id, home.id])
        XCTAssertEqual(model.settings.rules.map(\.action), [.off, .on])
        XCTAssertEqual(model.settings.rules.map(\.enabled), [false, true])
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.lastDecision, .none)
        XCTAssertEqual(store.savedSettings.last, model.settings)
    }

    @MainActor
    func testInvalidQuickEndpointLeavesSavedSettingsUnchanged() async {
        let initial = AppSettings(paused: true, launchAtLogin: false)
        let store = InMemorySettingsStore(initial)
        let model = AppModel(store: store)
        for port in ["", "abc", "0", "65536"] {
            XCTAssertFalse(model.setEndpoint(host: "127.0.0.1", portText: port))
        }
        XCTAssertFalse(model.setEndpoint(host: " \n ", portText: "7897"))
        XCTAssertEqual(model.settings, initial)
        XCTAssertEqual(store.saveCount, 0)
    }

}
