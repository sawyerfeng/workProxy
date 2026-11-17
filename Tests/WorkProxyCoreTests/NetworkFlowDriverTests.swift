import XCTest
@testable import WorkProxyCore

private actor GatedApplier: ProxyActionApplying {
    private var gate: CheckedContinuation<Void, Never>?
    private let started: XCTestExpectation
    private var shouldBlock = true
    private(set) var actions: [ProxyAction] = []

    init(started: XCTestExpectation) { self.started = started }

    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws {
        actions.append(action)
        if shouldBlock {
            shouldBlock = false
            await withCheckedContinuation {
                gate = $0
                started.fulfill()
            }
        }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

private struct DriverLocator: LocationRequesting {
    func requestLocation(timeout: Duration) async -> LocationResult { .unavailable(.unknown) }
}
private actor DriverNotifier: FailureNotifying {
    private(set) var failures: [String] = []
    func notifyFailure(_ message: String) async { failures.append(message) }
}
private struct FailingResetApplier: ProxyActionApplying {
    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws {
        XCTAssertEqual(action, .off)
        throw CocoaError(.fileWriteNoPermission)
    }
}

@MainActor
final class NetworkFlowDriverTests: XCTestCase {
    private let office = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Office")
    private let home = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Home")
    private let unknown = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Cafe")
    private var settings: AppSettings {
        AppSettings(rules: [
            Rule(name: "Office", network: .wifi(ssid: "Office"), action: .on),
            Rule(name: "Home", network: .wifi(ssid: "Home"), action: .on)
        ])
    }

    private func driver(applier: any ProxyActionApplying,
                        notifier: any FailureNotifying = DriverNotifier()) -> NetworkFlowDriver {
        NetworkFlowDriver(machine: NetworkFlowMachine(settings: settings),
                          endpoint: settings.endpoint, locator: DriverLocator(),
                          applier: applier, notifier: notifier)
    }

    private func waitForPhase(_ driver: NetworkFlowDriver,
                              _ matches: (NetworkFlowMachine.Phase) -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if matches(await driver.phase) { return }
            await Task.yield()
        }
        XCTFail("Network event was not processed")
    }

    func testRapidSwitchSkipsQueuedOldRuleAndEndsOffOnUnknownNetwork() async {
        let started = expectation(description: "First write started")
        let applier = GatedApplier(started: started)
        let driver = driver(applier: applier)
        let first = Task { await driver.send(.started(office)) }
        await fulfillment(of: [started], timeout: 2)
        let firstPhase = await driver.phase
        let oldRule = Task { await driver.send(.resume(home)) }
        await waitForPhase(driver) { $0 != firstPhase }
        let latest = Task { await driver.send(.networkChanged(unknown)) }
        await waitForPhase(driver) { if case .resetting(_, self.unknown) = $0 { true } else { false } }
        await applier.release()
        await first.value
        await oldRule.value
        await latest.value
        let actions = await applier.actions
        XCTAssertEqual(actions, [.on, .off])
        let phase = await driver.phase
        XCTAssertEqual(phase, .idle)
    }

    func testNewNetworkCannotEnableBeforeResetCompletesAndOldResetCannotApplyRules() async {
        let started = expectation(description: "Reset started")
        let applier = GatedApplier(started: started)
        let driver = driver(applier: applier)
        let first = Task { await driver.send(.networkChanged(office)) }
        await fulfillment(of: [started], timeout: 2)
        let latest = Task { await driver.send(.networkChanged(home)) }
        await waitForPhase(driver) { if case .resetting(_, self.home) = $0 { true } else { false } }
        let beforeRelease = await applier.actions
        XCTAssertEqual(beforeRelease, [.off])
        await applier.release()
        await first.value
        await latest.value
        let actions = await applier.actions
        XCTAssertEqual(actions, [.off, .off, .on])
        let decision = await driver.lastDecision
        guard case .action(.on, _) = decision else { return XCTFail("Expected current network rule") }
    }

    func testPauseWhileResetRunsPreventsSubsequentEnable() async {
        let started = expectation(description: "Reset started")
        let applier = GatedApplier(started: started)
        let driver = driver(applier: applier)
        let changing = Task { await driver.send(.networkChanged(office)) }
        await fulfillment(of: [started], timeout: 2)
        await driver.send(.pause)
        await applier.release()
        await changing.value
        let actions = await applier.actions
        XCTAssertEqual(actions, [.off])
    }

    func testResetFailureNotifiesOnceWithoutEnabling() async {
        let notifier = DriverNotifier()
        let driver = driver(applier: FailingResetApplier(), notifier: notifier)
        await driver.send(.networkChanged(office))
        await driver.send(.networkChanged(office))
        let failures = await notifier.failures
        let error = await driver.lastError
        XCTAssertEqual(failures.count, 1)
        XCTAssertNotNil(error)
    }
}
