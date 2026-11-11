import XCTest
@testable import WorkProxyCore

private actor RecordingApplier: ProxyActionApplying {
    var actions: [ProxyAction] = []
    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws {
        actions.append(action)
    }
}
private struct UnusedLocator: LocationRequesting {
    func requestLocation(timeout: Duration) async -> LocationResult { .unavailable(.unknown) }
}
private struct SilentNotifier: FailureNotifying {
    func notifyFailure(_ message: String) async {}
}

final class ManualProxyTests: XCTestCase {
    @MainActor
    func testManualControlPausesRulesAndResumeReappliesCurrentNetwork() async {
        let applier = RecordingApplier()
        let network = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Office")
        let settings = AppSettings(rules: [
            Rule(name: "Office", network: .wifi(ssid: "Office"), action: .on)
        ])
        let driver = NetworkFlowDriver(machine: NetworkFlowMachine(settings: settings),
                                       endpoint: settings.endpoint, locator: UnusedLocator(),
                                       applier: applier, notifier: SilentNotifier())
        await driver.send(.started(network))
        await driver.applyManually(.off)
        await driver.send(.networkChanged(network))
        let pausedActions = await applier.actions
        XCTAssertEqual(pausedActions, [.on, .off])
        await driver.send(.resume(network))
        let resumedActions = await applier.actions
        XCTAssertEqual(resumedActions, [.on, .off, .on])
    }
}
