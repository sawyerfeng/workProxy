import Foundation

public enum FlowEvent: Equatable, Sendable {
    case started(NetworkIdentity?)
    case networkChanged(NetworkIdentity?)
    case disconnected
    case woke(NetworkIdentity?)
    case pause
    case resume(NetworkIdentity?)
    case sleep
    case stabilizationElapsed(token: UUID)
    case locationResolved(token: UUID, result: LocationResult)
    case applySucceeded
    case applyFailed(String)
}

public enum FlowEffect: Equatable, Sendable {
    case scheduleStabilization(token: UUID, after: Duration)
    case cancelStabilization
    case requestLocation(token: UUID, timeout: Duration)
    case cancelLocation
    case apply(ProxyAction)
    case notifyFailure(String)
}

public struct FlowConfiguration: Sendable {
    public var stabilization: Duration
    public var locationTimeout: Duration

    public init(stabilization: Duration = .seconds(3),
                locationTimeout: Duration = .seconds(5)) {
        self.stabilization = stabilization
        self.locationTimeout = locationTimeout
    }

    public static let `default` = FlowConfiguration()
}

/// 纯状态机：输入网络/唤醒/启动/暂停事件，输出需要执行的效果。
/// 时钟由调用方提供，便于用确定时间验证 2/3/4 秒边界。
public struct NetworkFlowMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case waiting(token: UUID, identity: NetworkIdentity)
        case locating(token: UUID, identity: NetworkIdentity)
        case disconnected(token: UUID)
        case applying
    }

    private var settings: AppSettings
    private let configuration: FlowConfiguration
    private let engine: RuleEngine

    public private(set) var phase: Phase = .idle
    public private(set) var lastEvaluated: NetworkIdentity?
    public private(set) var lastDecision: RuleDecision = .none
    public private(set) var lastError: String?
    private var disconnectCandidate: NetworkIdentity?
    private var disconnectTimerFired = false

    public init(settings: AppSettings,
                configuration: FlowConfiguration = .default,
                engine: RuleEngine = RuleEngine()) {
        self.settings = settings
        self.configuration = configuration
        self.engine = engine
    }

    public var isPaused: Bool { settings.paused }
    public var rules: [Rule] { settings.rules }

    @discardableResult
    public mutating func update(settings: AppSettings) -> [FlowEffect] {
        self.settings = settings
        return settings.paused ? cancelPending() : []
    }

    public mutating func handle(_ event: FlowEvent, now: Date) -> [FlowEffect] {
        switch event {
        case let .started(identity):
            guard !settings.paused else { return cancelPending() }
            guard let identity else { return cancelPending() }
            return cancelPending() + evaluate(identity: identity, now: now,
                                              locationAttempted: false)

        case let .networkChanged(identity):
            return handleNetworkChanged(identity, now: now)

        case .disconnected:
            return handleDisconnected()

        case let .woke(identity):
            return handleWake(identity, now: now)

        case .pause:
            settings.paused = true
            return cancelPending()

        case .sleep:
            return cancelPending()

        case let .resume(identity):
            settings.paused = false
            guard let identity else { return cancelPending() }
            return cancelPending() + evaluate(identity: identity, now: now,
                                              locationAttempted: false)

        case let .stabilizationElapsed(token):
            return handleStabilizationElapsed(token, now: now)

        case let .locationResolved(token, result):
            return handleLocationResolved(token, result: result, now: now)

        case .applySucceeded:
            if case .applying = phase { phase = .idle }
            lastError = nil
            return []

        case let .applyFailed(message):
            let wasApplying: Bool
            if case .applying = phase {
                wasApplying = true
                phase = .idle
            } else {
                wasApplying = false
            }
            lastError = message
            return wasApplying ? [.notifyFailure(message)] : []
        }
    }

    // MARK: - Network changes

    private mutating func handleNetworkChanged(_ identity: NetworkIdentity?,
                                               now: Date) -> [FlowEffect] {
        guard !settings.paused else { return cancelPending() }
        guard let identity else { return handleDisconnected() }

        switch phase {
        case let .waiting(_, current) where current.isSamePhysicalNetwork(as: identity):
            return []
        case let .locating(_, current) where current.isSamePhysicalNetwork(as: identity):
            return []
        case .disconnected:
            if !disconnectTimerFired,
               let candidate = disconnectCandidate,
               candidate.isSamePhysicalNetwork(as: identity) {
                phase = .idle
                return [.cancelStabilization]
            }
            disconnectCandidate = nil
            disconnectTimerFired = false
            return scheduleStabilization(for: identity)
        case .idle, .applying:
            if let last = lastEvaluated, last.isSamePhysicalNetwork(as: identity) {
                return []
            }
            return scheduleStabilization(for: identity)
        case .waiting, .locating:
            return scheduleStabilization(for: identity)
        }
    }

    private mutating func handleDisconnected() -> [FlowEffect] {
        guard !settings.paused else { return cancelPending() }
        if case .disconnected = phase { return [] }

        let candidate: NetworkIdentity?
        switch phase {
        case let .waiting(_, identity), let .locating(_, identity):
            candidate = identity
        default:
            candidate = lastEvaluated
        }

        var effects: [FlowEffect] = []
        switch phase {
        case .locating: effects.append(.cancelLocation)
        case .waiting: effects.append(.cancelStabilization)
        default: break
        }

        disconnectCandidate = candidate
        disconnectTimerFired = false
        let token = UUID()
        phase = .disconnected(token: token)
        effects.append(.scheduleStabilization(token: token,
                                              after: configuration.stabilization))
        return effects
    }

    private mutating func handleWake(_ identity: NetworkIdentity?,
                                     now: Date) -> [FlowEffect] {
        guard !settings.paused else { return cancelPending() }
        guard let identity else { return cancelPending() }

        // 断线达到稳定阈值后唤醒：即使网络名相同也重新匹配。
        if case .disconnected = phase, disconnectTimerFired {
            return cancelPending() + evaluate(identity: identity, now: now,
                                              locationAttempted: false)
        }
        if let last = lastEvaluated, last.isSamePhysicalNetwork(as: identity) {
            return []
        }
        return cancelPending() + evaluate(identity: identity, now: now,
                                          locationAttempted: false)
    }

    private mutating func scheduleStabilization(for identity: NetworkIdentity) -> [FlowEffect] {
        var effects: [FlowEffect] = []
        switch phase {
        case .waiting, .disconnected: effects.append(.cancelStabilization)
        case .locating: effects.append(.cancelLocation)
        case .idle, .applying: break
        }
        let token = UUID()
        phase = .waiting(token: token, identity: identity)
        effects.append(.scheduleStabilization(token: token,
                                              after: configuration.stabilization))
        return effects
    }

    // MARK: - Evaluation

    private mutating func handleStabilizationElapsed(_ token: UUID,
                                                     now: Date) -> [FlowEffect] {
        switch phase {
        case let .waiting(current, identity) where current == token:
            return evaluate(identity: identity, now: now, locationAttempted: false)
        case let .disconnected(current) where current == token:
            disconnectTimerFired = true
            return []
        default:
            return []
        }
    }

    private mutating func handleLocationResolved(_ token: UUID, result: LocationResult,
                                                 now: Date) -> [FlowEffect] {
        guard case let .locating(current, identity) = phase, current == token else {
            return []
        }
        let fix: LocationFix?
        switch result {
        case let .fix(value): fix = value
        case .unavailable: fix = nil
        }
        return finish(identity: identity, now: now, location: fix)
    }

    private mutating func evaluate(identity: NetworkIdentity, now: Date,
                                   locationAttempted: Bool) -> [FlowEffect] {
        if !locationAttempted,
           engine.mayRequireLocation(rules: settings.rules, identity: identity) {
            let token = UUID()
            phase = .locating(token: token, identity: identity)
            return [.requestLocation(token: token,
                                     timeout: configuration.locationTimeout)]
        }
        return finish(identity: identity, now: now, location: nil)
    }

    private mutating func finish(identity: NetworkIdentity, now: Date,
                                 location: LocationFix?) -> [FlowEffect] {
        lastEvaluated = identity
        let decision = engine.decide(rules: settings.rules, identity: identity,
                                     location: location, now: now)
        lastDecision = decision
        switch decision {
        case .none:
            phase = .idle
            return []
        case let .action(action, _):
            phase = .applying
            return [.apply(action)]
        }
    }

    private mutating func cancelPending() -> [FlowEffect] {
        var effects: [FlowEffect] = []
        switch phase {
        case .waiting, .disconnected: effects.append(.cancelStabilization)
        case .locating: effects.append(.cancelLocation)
        case .idle, .applying: break
        }
        phase = .idle
        return effects
    }
}

// MARK: - Driver

@MainActor
public protocol LocationRequesting: Sendable {
    func requestLocation(timeout: Duration) async -> LocationResult
}

public protocol ProxyActionApplying: Sendable {
    func apply(_ action: ProxyAction, endpoint: ProxyEndpoint) async throws
}

public protocol FailureNotifying: Sendable {
    func notifyFailure(_ message: String) async
}

/// 把纯状态机接到真实时钟、定位、系统代理和通知上。
public actor NetworkFlowDriver {
    private var machine: NetworkFlowMachine
    private var endpoint: ProxyEndpoint
    private let locator: any LocationRequesting
    private let applier: any ProxyActionApplying
    private let notifier: any FailureNotifying
    private var timerTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    public init(machine: NetworkFlowMachine, endpoint: ProxyEndpoint,
                locator: any LocationRequesting,
                applier: any ProxyActionApplying,
                notifier: any FailureNotifying) {
        self.machine = machine
        self.endpoint = endpoint
        self.locator = locator
        self.applier = applier
        self.notifier = notifier
    }

    public var phase: NetworkFlowMachine.Phase { machine.phase }
    public var lastDecision: RuleDecision { machine.lastDecision }
    public var lastError: String? { machine.lastError }

    public func send(_ event: FlowEvent) async {
        let effects = machine.handle(event, now: Date())
        await execute(effects)
    }

    public func update(settings: AppSettings) async {
        endpoint = settings.endpoint
        let effects = machine.update(settings: settings)
        await execute(effects)
    }

    private func execute(_ effects: [FlowEffect]) async {
        for effect in effects {
            switch effect {
            case let .scheduleStabilization(token, after):
                timerTask?.cancel()
                timerTask = Task { [weak self] in
                    do { try await Task.sleep(for: after) } catch { return }
                    await self?.send(.stabilizationElapsed(token: token))
                }
            case .cancelStabilization:
                timerTask?.cancel()
                timerTask = nil
            case let .requestLocation(token, timeout):
                locationTask?.cancel()
                locationTask = Task { [weak self] in
                    guard let self else { return }
                    let result = await self.locator.requestLocation(timeout: timeout)
                    guard !Task.isCancelled else { return }
                    await self.send(.locationResolved(token: token, result: result))
                }
            case .cancelLocation:
                locationTask?.cancel()
                locationTask = nil
            case let .apply(action):
                do {
                    try await applier.apply(action, endpoint: endpoint)
                    await send(.applySucceeded)
                } catch {
                    await send(.applyFailed(error.localizedDescription))
                }
            case let .notifyFailure(message):
                await notifier.notifyFailure(message)
            }
        }
    }
}
