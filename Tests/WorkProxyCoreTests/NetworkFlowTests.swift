import XCTest
@testable import WorkProxyCore

final class NetworkFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var office: NetworkIdentity {
        NetworkIdentity(interfaceName: "en0", serviceName: "Wi-Fi", kind: .wifi, ssid: "Office")
    }

    private var home: NetworkIdentity {
        NetworkIdentity(interfaceName: "en0", serviceName: "Wi-Fi", kind: .wifi, ssid: "Home")
    }

    private var wired: NetworkIdentity {
        NetworkIdentity(interfaceName: "en7", serviceName: "USB LAN", kind: .wired)
    }

    private func officeRule(_ action: ProxyAction = .on) -> Rule {
        Rule(name: "Office", network: .wifi(ssid: "Office"), action: action)
    }

    private func homeRule(_ action: ProxyAction = .off) -> Rule {
        Rule(name: "Home", network: .wifi(ssid: "Home"), action: action)
    }

    private func wiringRule(_ action: ProxyAction = .off) -> Rule {
        Rule(name: "Wired", network: .wired(interfaceName: "en7"), action: action)
    }

    private func machine(rules: [Rule], paused: Bool = false) -> NetworkFlowMachine {
        NetworkFlowMachine(settings: AppSettings(rules: rules, paused: paused))
    }

    private func stabilizationToken(_ effects: [FlowEffect]) -> UUID? {
        for effect in effects {
            if case let .scheduleStabilization(token, _) = effect { return token }
        }
        return nil
    }

    private func locationToken(_ effects: [FlowEffect]) -> UUID? {
        for effect in effects {
            if case let .requestLocation(token, _) = effect { return token }
        }
        return nil
    }

    private var insideOffice: LocationFix {
        LocationFix(latitude: 31.2304, longitude: 121.4737,
                    horizontalAccuracy: 10, timestamp: now)
    }

    func testStartAppliesImmediately() {
        let rule = officeRule(.on)
        var machine = machine(rules: [rule])

        let effects = machine.handle(.started(office), now: now)

        XCTAssertEqual(effects, [.apply(.on)])
        XCTAssertEqual(machine.lastDecision, .action(.on, ruleID: rule.id))
    }

    func testNetworkChangeWaitsForStabilization() {
        var machine = machine(rules: [officeRule(.on)])

        let scheduled = machine.handle(.networkChanged(office), now: now)
        let token = stabilizationToken(scheduled)
        XCTAssertNotNil(token)
        XCTAssertFalse(scheduled.contains(.apply(.on)))

        let applied = machine.handle(.stabilizationElapsed(token: token!), now: now)
        XCTAssertEqual(applied, [.apply(.on)])
    }

    func testSameNetworkPathUpdateDoesNotResetWaiting() {
        var machine = machine(rules: [officeRule(.on)])
        let token = stabilizationToken(machine.handle(.networkChanged(office), now: now))

        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: token!), now: now),
                       [.apply(.on)])
    }

    func testSameNetworkPathUpdateAfterApplyDoesNothing() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])
    }

    func testShortDisconnectThenSameNetworkDoesNotApply() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        let disconnected = machine.handle(.disconnected, now: now)
        XCTAssertNotNil(stabilizationToken(disconnected))

        let reconnect = machine.handle(.networkChanged(office), now: now)
        XCTAssertEqual(reconnect, [.cancelStabilization])
    }

    func testLongDisconnectThenSameNetworkRematches() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        let disconnectToken = stabilizationToken(machine.handle(.disconnected, now: now))!
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: disconnectToken), now: now), [])

        let reconnect = machine.handle(.networkChanged(office), now: now)
        let reconnectToken = stabilizationToken(reconnect)
        XCTAssertNotNil(reconnectToken)
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: reconnectToken!), now: now),
                       [.apply(.on)])
    }

    func testDisconnectThenDifferentNetworkAppliesAfterStabilization() {
        var machine = machine(rules: [officeRule(.on), homeRule(.off)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        let disconnectToken = stabilizationToken(machine.handle(.disconnected, now: now))!
        _ = machine.handle(.stabilizationElapsed(token: disconnectToken), now: now)

        let reconnectToken = stabilizationToken(machine.handle(.networkChanged(home), now: now))!
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: reconnectToken), now: now),
                       [.apply(.off)])
    }

    func testPauseDoesNothingAndResumeAppliesImmediately() {
        var machine = machine(rules: [officeRule(.on)], paused: true)

        XCTAssertEqual(machine.handle(.networkChanged(office), now: now), [])

        let resumed = machine.handle(.resume(office), now: now)
        XCTAssertEqual(resumed, [.apply(.on)])
    }

    func testPauseCancelsPendingStabilization() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.networkChanged(office), now: now)

        XCTAssertEqual(machine.handle(.pause, now: now), [.cancelStabilization])
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: UUID()), now: now), [])
    }

    func testWakeOnSameNetworkDoesNothing() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        XCTAssertEqual(machine.handle(.woke(office), now: now), [])
    }

    func testWakeOnDifferentNetworkApplies() {
        var machine = machine(rules: [officeRule(.on), wiringRule(.off)])
        _ = machine.handle(.started(office), now: now)
        _ = machine.handle(.applySucceeded, now: now)

        XCTAssertEqual(machine.handle(.woke(wired), now: now), [.apply(.off)])
    }

    func testLocationRuleRequestsLocationBeforeApplying() {
        let place = PlaceCondition(label: "Office", latitude: 31.2304,
                                   longitude: 121.4737, radiusMeters: 100)
        let rule = Rule(name: "Office place", network: .wifi(ssid: "Office"),
                        place: place, action: .on)
        var machine = machine(rules: [rule])

        let started = machine.handle(.started(office), now: now)
        let token = locationToken(started)
        XCTAssertNotNil(token)
        XCTAssertFalse(started.contains(.apply(.on)))

        let applied = machine.handle(.locationResolved(token: token!, result: .fix(insideOffice)),
                                     now: now)
        XCTAssertEqual(applied, [.apply(.on)])
    }

    func testLocationUnavailableFallsThroughToUnconditionalRule() {
        let place = PlaceCondition(label: "Office", latitude: 31.2304,
                                   longitude: 121.4737, radiusMeters: 100)
        let locationRule = Rule(name: "Office place", network: .wifi(ssid: "Office"),
                                place: place, action: .on)
        let fallback = officeRule(.off)
        var machine = machine(rules: [locationRule, fallback])

        let token = locationToken(machine.handle(.started(office), now: now))!
        let applied = machine.handle(
            .locationResolved(token: token, result: .unavailable(.timeout)), now: now
        )

        XCTAssertEqual(applied, [.apply(.off)])
    }

    func testLateLocationResultIsIgnoredAfterNetworkChange() {
        let place = PlaceCondition(label: "Office", latitude: 31.2304,
                                   longitude: 121.4737, radiusMeters: 100)
        let officeLocation = Rule(name: "Office place", network: .wifi(ssid: "Office"),
                                  place: place, action: .on)
        var machine = machine(rules: [officeLocation, homeRule(.off)])

        let token = locationToken(machine.handle(.started(office), now: now))!
        _ = machine.handle(.networkChanged(home), now: now)

        XCTAssertEqual(machine.handle(.locationResolved(token: token,
                                                        result: .fix(insideOffice)), now: now),
                       [])
    }

    func testNoMatchingRuleProducesNoActionOrNotification() {
        var machine = machine(rules: [officeRule(.on)])

        let effects = machine.handle(.started(home), now: now)

        XCTAssertEqual(effects, [])
        XCTAssertEqual(machine.lastDecision, .none)
    }

    func testApplyFailureNotifiesOnce() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.started(office), now: now)

        XCTAssertEqual(machine.handle(.applyFailed("boom"), now: now),
                       [.notifyFailure("boom")])
        XCTAssertEqual(machine.handle(.applyFailed("boom"), now: now), [])
    }

    func testStaleStabilizationTokenIsIgnored() {
        var machine = machine(rules: [officeRule(.on), homeRule(.off)])
        let first = stabilizationToken(machine.handle(.networkChanged(office), now: now))!
        let second = stabilizationToken(machine.handle(.networkChanged(home), now: now))!

        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: first), now: now), [])
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: second), now: now),
                       [.apply(.off)])
    }

    func testSleepCancelsPendingWithoutApplying() {
        var machine = machine(rules: [officeRule(.on)])
        _ = machine.handle(.networkChanged(office), now: now)

        XCTAssertEqual(machine.handle(.sleep, now: now), [.cancelStabilization])
        XCTAssertEqual(machine.handle(.stabilizationElapsed(token: UUID()), now: now), [])
    }

    func testWiredNetworkUsesWiredRule() {
        var machine = machine(rules: [wiringRule(.off)])

        XCTAssertEqual(machine.handle(.started(wired), now: now), [.apply(.off)])
    }
}
