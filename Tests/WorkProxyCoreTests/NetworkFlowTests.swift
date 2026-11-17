import XCTest
@testable import WorkProxyCore

final class NetworkFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let office = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Office")
    private let home = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Home")
    private let wired = NetworkIdentity(interfaceName: "en7", kind: .wired)

    private func machine(paused: Bool = false, location: Bool = false) -> NetworkFlowMachine {
        let place = location ? PlaceCondition(label: "Office", latitude: 31.2304,
                                              longitude: 121.4737, radiusMeters: 100) : nil
        return NetworkFlowMachine(settings: AppSettings(rules: [
            Rule(name: "Office", network: .wifi(ssid: "Office"), place: place, action: .on),
            Rule(name: "Home", network: .wifi(ssid: "Home"), action: .off),
            Rule(name: "Wired", network: .wired(interfaceName: "en7"), action: .on)
        ], paused: paused))
    }

    private func actions(_ effects: [FlowEffect]) -> [ProxyAction] {
        effects.compactMap { if case let .apply(action, _) = $0 { action } else { nil } }
    }

    private func applicationToken(_ effects: [FlowEffect]) throws -> UUID {
        try XCTUnwrap(effects.compactMap {
            if case let .apply(_, token) = $0 { token } else { nil }
        }.first)
    }

    private func locationToken(_ effects: [FlowEffect]) throws -> UUID {
        try XCTUnwrap(effects.compactMap {
            if case let .requestLocation(token, _) = $0 { token } else { nil }
        }.first)
    }

    @discardableResult
    private func succeed(_ machine: inout NetworkFlowMachine,
                         _ effects: [FlowEffect]) throws -> [FlowEffect] {
        machine.handle(.applySucceeded(token: try applicationToken(effects)), now: now)
    }

    func testStartAndResumeApplyImmediatelyWithoutReset() {
        var machine = machine()
        XCTAssertEqual(actions(machine.handle(.started(office), now: now)), [.on])
        _ = machine.handle(.pause, now: now)
        XCTAssertEqual(actions(machine.handle(.resume(wired), now: now)), [.on])
    }

    func testNetworkChangeClosesBeforeApplyingRuleWithoutTimer() throws {
        var machine = machine()
        let reset = machine.handle(.networkChanged(office), now: now)
        XCTAssertEqual(actions(reset), [.off])
        XCTAssertEqual(machine.lastDecision, .none)
        let rule = try succeed(&machine, reset)
        XCTAssertEqual(actions(rule), [.on])
        try succeed(&machine, rule)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testOffRuleKeepsProxyOffWithoutSecondWrite() throws {
        var machine = machine()
        let reset = machine.handle(.networkChanged(home), now: now)
        XCTAssertEqual(actions(reset), [.off])
        XCTAssertEqual(try succeed(&machine, reset), [])
        guard case .action(.off, _) = machine.lastDecision else {
            return XCTFail("Expected the Home off rule")
        }
    }

    func testDisconnectClosesImmediatelyAndDuplicateDisconnectDoesNothing() throws {
        var machine = machine()
        let reset = machine.handle(.disconnected, now: now)
        XCTAssertEqual(actions(reset), [.off])
        XCTAssertEqual(machine.handle(.networkChanged(nil), now: now), [])
        try succeed(&machine, reset)
        XCTAssertEqual(machine.phase, .disconnected)
        XCTAssertEqual(machine.handle(.disconnected, now: now), [])
    }

    func testSameNetworkReconnectRematchesRegardlessOfDisconnectDuration() throws {
        for seconds in [0.0, 2.0, 3.0, 4.0] {
            var machine = machine()
            let start = machine.handle(.started(office), now: now)
            try succeed(&machine, start)
            let disconnect = machine.handle(.disconnected, now: now)
            try succeed(&machine, disconnect)
            let reset = machine.handle(.networkChanged(office), now: now.addingTimeInterval(seconds))
            XCTAssertEqual(actions(reset), [.off])
            XCTAssertEqual(actions(try succeed(&machine, reset)), [.on])
        }
    }

    func testSameNetworkCallbacksDoNotInterruptResetLocationOrRuleApply() throws {
        var machine = machine(location: true)
        let reset = machine.handle(.networkChanged(office), now: now)
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
        let locating = try succeed(&machine, reset)
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
        let rule = machine.handle(.locationResolved(token: try locationToken(locating),
                                  result: .fix(insideOffice)), now: now)
        XCTAssertEqual(actions(rule), [.on])
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
        try succeed(&machine, rule)
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
    }

    func testUnknownNetworkStaysOffButStartupWithNoRuleKeepsExistingState() throws {
        let unknown = NetworkIdentity(interfaceName: "en0", kind: .wifi, ssid: "Cafe")
        var machine = machine()
        XCTAssertEqual(machine.handle(.started(unknown), now: now), [])
        let reset = machine.handle(.networkChanged(home), now: now)
        try succeed(&machine, reset)
        let unknownReset = machine.handle(.networkChanged(unknown), now: now)
        XCTAssertEqual(actions(unknownReset), [.off])
        XCTAssertEqual(try succeed(&machine, unknownReset), [])
        XCTAssertEqual(machine.lastDecision, .none)
    }

    func testPauseDoesNothingAndInvalidatesPendingReset() throws {
        var machine = machine(paused: true)
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
        XCTAssertEqual(machine.handle(.disconnected, now: now), [])
        XCTAssertEqual(machine.handle(.woke(wired), now: now), [])
        _ = machine.handle(.resume(home), now: now)
        let reset = machine.handle(.networkChanged(office), now: now)
        XCTAssertEqual(machine.handle(.pause, now: now), [])
        XCTAssertEqual(try succeed(&machine, reset), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testSleepInvalidatesResetAndSameNetworkWakeDoesNotReapply() throws {
        var machine = machine()
        let start = machine.handle(.started(office), now: now)
        try succeed(&machine, start)
        XCTAssertEqual(machine.handle(.sleep, now: now), [])
        XCTAssertEqual(machine.handle(.woke(office), now: now), [])
        let reset = machine.handle(.networkChanged(wired), now: now)
        _ = machine.handle(.sleep, now: now)
        XCTAssertEqual(try succeed(&machine, reset), [])
        let wake = machine.handle(.woke(wired), now: now)
        XCTAssertEqual(actions(wake), [.off])
        XCTAssertEqual(actions(try succeed(&machine, wake)), [.on])
    }

    func testWakeOnDifferentNetworkClosesBeforeRuleAndOfflineWakeCloses() throws {
        var machine = machine()
        _ = machine.handle(.started(office), now: now)
        let reset = machine.handle(.woke(wired), now: now)
        XCTAssertEqual(actions(reset), [.off])
        XCTAssertEqual(actions(try succeed(&machine, reset)), [.on])
        XCTAssertEqual(actions(machine.handle(.woke(nil), now: now)), [.off])
    }

    private var insideOffice: LocationFix {
        LocationFix(latitude: 31.2304, longitude: 121.4737,
                    horizontalAccuracy: 10, timestamp: now)
    }

    func testLocationStartsOnlyAfterProxyIsClosedAndTimeoutKeepsItOff() throws {
        var machine = machine(location: true)
        let reset = machine.handle(.networkChanged(office), now: now)
        XCTAssertEqual(reset.count, 1)
        let locating = try succeed(&machine, reset)
        let token = try locationToken(locating)
        XCTAssertEqual(locating, [.requestLocation(token: token, timeout: .seconds(5))])
        XCTAssertEqual(machine.handle(.locationResolved(token: token, result: .unavailable(.timeout)),
                                      now: now), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testLocationUnavailableStillFallsThroughToOffRule() throws {
        let place = PlaceCondition(label: "Office", latitude: 31.2304,
                                   longitude: 121.4737, radiusMeters: 100)
        var machine = NetworkFlowMachine(settings: AppSettings(rules: [
            Rule(name: "Place", network: .wifi(ssid: "Office"), place: place, action: .on),
            Rule(name: "Fallback", network: .wifi(ssid: "Office"), action: .off)
        ]))
        let locating = machine.handle(.started(office), now: now)
        let result = machine.handle(.locationResolved(token: try locationToken(locating),
                                    result: .unavailable(.denied)), now: now)
        XCTAssertEqual(actions(result), [.off])
    }

    func testNetworkChangeCancelsLocationAndIgnoresLateResult() throws {
        var machine = machine(location: true)
        let locating = machine.handle(.started(office), now: now)
        let changed = machine.handle(.networkChanged(home), now: now)
        XCTAssertEqual(changed.first, .cancelLocation)
        XCTAssertEqual(actions(changed), [.off])
        XCTAssertEqual(machine.handle(.locationResolved(token: try locationToken(locating),
                                      result: .fix(insideOffice)), now: now), [])
        XCTAssertEqual(try succeed(&machine, changed), [])
    }

    func testPauseAndSleepCancelLocationAndIgnoreLateResults() throws {
        for event: FlowEvent in [.pause, .sleep] {
            var machine = machine(location: true)
            let locating = machine.handle(.started(office), now: now)
            XCTAssertEqual(machine.handle(event, now: now), [.cancelLocation])
            XCTAssertEqual(machine.handle(.locationResolved(token: try locationToken(locating),
                                          result: .fix(insideOffice)), now: now), [])
        }
    }

    func testRapidNetworkChangesIgnoreOldSuccessAndFailure() throws {
        var machine = machine()
        let first = machine.handle(.networkChanged(office), now: now)
        let latest = machine.handle(.networkChanged(wired), now: now)
        let token = try applicationToken(first)
        XCTAssertEqual(machine.handle(.applySucceeded(token: token), now: now), [])
        XCTAssertEqual(machine.handle(.applyFailed(token: token, message: "old"), now: now), [])
        XCTAssertNil(machine.lastError)
        XCTAssertEqual(actions(try succeed(&machine, latest)), [.on])
    }

    func testResetFailureNotifiesOnceAndDoesNotEnableOrRetry() throws {
        var machine = machine()
        let reset = machine.handle(.networkChanged(office), now: now)
        let token = try applicationToken(reset)
        XCTAssertEqual(machine.handle(.applyFailed(token: token, message: "boom"), now: now),
                       [.notifyFailure("boom")])
        XCTAssertEqual(machine.lastError, "boom")
        XCTAssertEqual(machine.handle(.applyFailed(token: token, message: "boom"), now: now), [])
        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
    }
}
