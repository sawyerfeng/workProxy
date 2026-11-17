import Foundation

public enum FlowEvent: Equatable, Sendable {
    case started(NetworkIdentity?)
    case networkChanged(NetworkIdentity?)
    case disconnected
    case woke(NetworkIdentity?)
    case pause
    case resume(NetworkIdentity?)
    case sleep
    case manualApply(ProxyAction)
    case locationResolved(token: UUID, result: LocationResult)
    case applySucceeded(token: UUID)
    case applyFailed(token: UUID, message: String)
}

public enum FlowEffect: Equatable, Sendable {
    case requestLocation(token: UUID, timeout: Duration)
    case cancelLocation
    case apply(ProxyAction, token: UUID)
    case notifyFailure(String)
}

public struct FlowConfiguration: Sendable {
    public var locationTimeout: Duration

    public init(locationTimeout: Duration = .seconds(5)) {
        self.locationTimeout = locationTimeout
    }

    public static let `default` = FlowConfiguration()
}

/// 纯状态机：切网先关闭代理，关闭成功后按已连接网络匹配规则。
public struct NetworkFlowMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case resetting(token: UUID, identity: NetworkIdentity?)
        case locating(token: UUID, identity: NetworkIdentity, proxyIsOff: Bool)
        case disconnected
        case applying(token: UUID)
    }

    private var settings: AppSettings
    private let configuration: FlowConfiguration
    private let engine: RuleEngine
    private var currentIdentity: NetworkIdentity?

    public private(set) var phase: Phase = .idle
    public private(set) var lastEvaluated: NetworkIdentity?
    public private(set) var lastDecision: RuleDecision = .none
    public private(set) var lastError: String?

    public init(settings: AppSettings,
                configuration: FlowConfiguration = .default,
                engine: RuleEngine = RuleEngine()) {
        self.settings = settings
        self.configuration = configuration
        self.engine = engine
    }

    public var isPaused: Bool { settings.paused }
    public var rules: [Rule] { settings.rules }

    fileprivate func isCurrentApplication(_ token: UUID) -> Bool {
        switch phase {
        case let .resetting(current, _), let .applying(current):
            return current == token
        default:
            return false
        }
    }

    @discardableResult
    public mutating func update(settings: AppSettings) -> [FlowEffect] {
        self.settings = settings
        return settings.paused ? cancelPending() : []
    }

    public mutating func handle(_ event: FlowEvent, now: Date) -> [FlowEffect] {
        switch event {
        case let .started(identity):
            guard !settings.paused else { return cancelPending() }
            return evaluateCurrent(identity, now: now)

        case let .networkChanged(identity), let .woke(identity):
            guard !settings.paused else { return cancelPending() }
            if let identity, let currentIdentity,
               currentIdentity.isSamePhysicalNetwork(as: identity) { return [] }
            if identity == nil {
                if case .disconnected = phase { return [] }
                if case .resetting(_, nil) = phase { return [] }
            }
            let effects = cancelPending()
            currentIdentity = identity
            lastDecision = .none
            let token = UUID()
            phase = .resetting(token: token, identity: identity)
            return effects + [.apply(.off, token: token)]

        case .disconnected:
            return handle(.networkChanged(nil), now: now)

        case .pause:
            settings.paused = true
            return cancelPending()

        case .sleep:
            if phase != .idle && phase != .disconnected { currentIdentity = nil }
            return cancelPending()

        case let .resume(identity):
            settings.paused = false
            return evaluateCurrent(identity, now: now)

        case let .manualApply(action):
            settings.paused = true
            let effects = cancelPending()
            let token = UUID()
            phase = .applying(token: token)
            return effects + [.apply(action, token: token)]

        case let .locationResolved(token, result):
            guard case let .locating(current, identity, proxyIsOff) = phase,
                  current == token else { return [] }
            let fix: LocationFix?
            switch result {
            case let .fix(value): fix = value
            case .unavailable: fix = nil
            }
            return finish(identity: identity, now: now, location: fix, proxyIsOff: proxyIsOff)

        case let .applySucceeded(token):
            guard isCurrentApplication(token) else { return [] }
            lastError = nil
            if case let .resetting(_, identity) = phase {
                guard let identity else {
                    phase = .disconnected
                    return []
                }
                return evaluate(identity: identity, now: now, proxyIsOff: true)
            }
            phase = .idle
            return []

        case let .applyFailed(token, message):
            guard isCurrentApplication(token) else { return [] }
            if case .resetting(_, nil) = phase {
                phase = .disconnected
            } else {
                phase = .idle
            }
            lastError = message
            return [.notifyFailure(message)]
        }
    }

    private mutating func evaluateCurrent(_ identity: NetworkIdentity?, now: Date) -> [FlowEffect] {
        let effects = cancelPending()
        currentIdentity = identity
        guard let identity else { return effects }
        return effects + evaluate(identity: identity, now: now, proxyIsOff: false)
    }

    private mutating func evaluate(identity: NetworkIdentity, now: Date,
                                   proxyIsOff: Bool) -> [FlowEffect] {
        if engine.mayRequireLocation(rules: settings.rules, identity: identity) {
            let token = UUID()
            phase = .locating(token: token, identity: identity, proxyIsOff: proxyIsOff)
            return [.requestLocation(token: token, timeout: configuration.locationTimeout)]
        }
        return finish(identity: identity, now: now, location: nil, proxyIsOff: proxyIsOff)
    }

    private mutating func finish(identity: NetworkIdentity, now: Date,
                                 location: LocationFix?, proxyIsOff: Bool) -> [FlowEffect] {
        lastEvaluated = identity
        lastDecision = engine.decide(rules: settings.rules, identity: identity,
                                     location: location, now: now)
        phase = .idle
        guard case let .action(action, _) = lastDecision,
              !(proxyIsOff && action == .off) else { return [] }
        let token = UUID()
        phase = .applying(token: token)
        return [.apply(action, token: token)]
    }

    private mutating func cancelPending() -> [FlowEffect] {
        let effects: [FlowEffect]
        if case .locating = phase { effects = [.cancelLocation] } else { effects = [] }
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

/// 串行写入代理；过期任务在写入前和回传结果前核对网络令牌。
public actor NetworkFlowDriver {
    private var machine: NetworkFlowMachine
    private var endpoint: ProxyEndpoint
    private let locator: any LocationRequesting
    private let applier: any ProxyActionApplying
    private let notifier: any FailureNotifying
    private var locationTask: Task<Void, Never>?
    private var applyTask: Task<Void, Error>?

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

    public func applyManually(_ action: ProxyAction) async {
        await send(.manualApply(action))
    }

    private func applySerially(_ action: ProxyAction, token: UUID) async throws {
        let previous = applyTask
        let applier = self.applier
        let endpoint = self.endpoint
        let task = Task {
            _ = try? await previous?.value
            guard self.machine.isCurrentApplication(token) else { return }
            try await applier.apply(action, endpoint: endpoint)
        }
        applyTask = task
        try await task.value
    }

    private func execute(_ effects: [FlowEffect]) async {
        for effect in effects {
            switch effect {
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
            case let .apply(action, token):
                do {
                    try await applySerially(action, token: token)
                    await send(.applySucceeded(token: token))
                } catch {
                    await send(.applyFailed(token: token, message: error.localizedDescription))
                }
            case let .notifyFailure(message):
                await notifier.notifyFailure(message)
            }
        }
    }
}
