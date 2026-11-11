import AppKit
import Foundation
import SwiftUI
import WorkProxyCore

struct RuleEditorTarget: Identifiable {
    let id = UUID()
    let rule: Rule?
}

enum SystemProxyState {
    case on
    case off
    case mixed
    case unknown
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var currentNetwork: NetworkIdentity?
    @Published private(set) var statusText = "等待网络事件"
    @Published private(set) var lastError: String?
    @Published private(set) var lastDecision: RuleDecision = .none
    @Published private(set) var availableServices: [NetworkService] = []
    @Published private(set) var knownWiFiNetworks: [String] = []
    @Published private(set) var effectiveProxy: EffectiveProxy?
    @Published private(set) var endpointReachable: Bool?
    @Published private(set) var loginItemStatus = "未知"
    @Published private(set) var notificationAuthorized = false
    @Published private(set) var locationAuthorized = false
    @Published var editingRule: RuleEditorTarget? {
        didSet {
            if editingRule != nil { refreshWiFiNetworks() }
        }
    }

    let locationService: LocationService

    private let store: any SettingsStoring
    private let setup: Networksetup
    private let monitor: NetworkMonitor
    private let notificationService = NotificationService()
    private let driver: NetworkFlowDriver
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var statusTask: Task<Void, Never>?
    private var started = false
    private var reachabilityTick = 0

    init(store: any SettingsStoring = JSONSettingsStore(url: JSONSettingsStore.defaultURL())) {
        let loaded = (try? store.load()) ?? .default
        let setup = Networksetup()
        let location = LocationService()
        self.store = store
        self.settings = loaded
        self.setup = setup
        self.monitor = NetworkMonitor(setup: setup)
        self.locationService = location
        self.driver = NetworkFlowDriver(
            machine: NetworkFlowMachine(settings: loaded),
            endpoint: loaded.endpoint,
            locator: location,
            applier: SystemProxyActionApplier(setup: setup),
            notifier: notificationService
        )
    }

    var isPaused: Bool { settings.paused }

    var menuBarIcon: String {
        if lastError != nil { return "exclamationmark.triangle" }
        if settings.paused { return "pause.circle" }
        if case .action(.on, _) = lastDecision { return "network" }
        if case .action(.off, _) = lastDecision { return "network.slash" }
        return "network"
    }

    var currentNetworkDescription: String {
        guard let network = currentNetwork else { return "无主要网络" }
        switch network.kind {
        case .wifi:
            return network.ssid.map { "Wi-Fi：\($0)" } ?? "Wi-Fi（名称不可读）"
        case .wired:
            return "有线：\(network.serviceName ?? network.interfaceName)"
        case .other:
            return network.serviceName ?? network.interfaceName
        }
    }

    var systemProxyState: SystemProxyState {
        guard let proxy = effectiveProxy else { return .unknown }
        if proxy.http && proxy.https && proxy.socks { return .on }
        if !proxy.http && !proxy.https && !proxy.socks
            && !proxy.pac && !proxy.autoDiscovery {
            return .off
        }
        return .mixed
    }

    var systemProxySummary: String {
        switch systemProxyState {
        case .on:
            if let server = effectiveProxy?.server, let port = effectiveProxy?.port {
                return "系统代理已开启 · \(server):\(port)"
            }
            return "系统代理已开启"
        case .off:
            return "系统代理已关闭"
        case .mixed:
            return "系统代理处于部分开启状态"
        case .unknown:
            return "无法读取系统代理状态"
        }
    }

    var enabledRuleCount: Int {
        settings.rules.filter(\.enabled).count
    }

    var endpointStatusText: String {
        switch endpointReachable {
        case true: return "可连接"
        case false: return "不可连接"
        case nil: return "检测中…"
        }
    }

    func start() {
        guard !started else { return }
        started = true

        monitor.onChange = { [weak self] identity in
            Task { @MainActor in await self?.networkChanged(identity) }
        }
        monitor.start()
        currentNetwork = monitor.currentIdentity
        refreshServices()
        refreshWiFiNetworks()
        refreshLoginItemStatus()
        refreshEffectiveProxy()
        refreshEndpointReachability()
        registerSleepWake()

        Task {
            await driver.send(.started(monitor.currentIdentity))
            await refreshRuntimeStatus()
            notificationAuthorized = await notificationService.isAuthorized()
        }

        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.refreshRuntimeStatus()
                self.locationAuthorized = self.locationService.isAuthorized
                self.refreshEffectiveProxy()
                self.reachabilityTick += 1
                if self.reachabilityTick % 10 == 0 {
                    self.refreshEndpointReachability()
                }
            }
        }

        if settings.launchAtLogin, Self.isInstalledLocation {
            try? LoginItemService.setEnabled(true)
            refreshLoginItemStatus()
        } else if !Self.isInstalledLocation {
            loginItemStatus = "开发构建（未自动注册）"
        }
    }

    private static var isInstalledLocation: Bool {
        let path = Bundle.main.bundlePath
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path + "/"
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications)
    }

    func stop() {
        statusTask?.cancel()
        statusTask = nil
        monitor.stop()
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver { center.removeObserver(sleepObserver) }
        if let wakeObserver { center.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
    }

    private func networkChanged(_ identity: NetworkIdentity?) async {
        currentNetwork = identity
        if let identity {
            await driver.send(.networkChanged(identity))
        } else {
            await driver.send(.disconnected)
        }
        await refreshRuntimeStatus()
    }

    private func refreshRuntimeStatus() async {
        let phase = await driver.phase
        let decision = await driver.lastDecision
        let error = await driver.lastError
        lastDecision = decision
        lastError = error

        switch phase {
        case .idle:
            switch decision {
            case let .action(action, ruleID):
                let name = settings.rules.first { $0.id == ruleID }?.name ?? "规则"
                statusText = "\(name)：\(action.displayName)"
            case .none:
                statusText = "无匹配规则，保持现状"
            }
        case .waiting:
            statusText = "网络变化，等待稳定 3 秒…"
        case .locating:
            statusText = "正在获取位置…"
        case .disconnected:
            statusText = "网络已断开"
        case .applying:
            statusText = "正在应用代理…"
        }
    }

    private func registerSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.driver.send(.sleep) }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification,
                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.monitor.refresh()
                await self.driver.send(.woke(self.monitor.currentIdentity))
                await self.refreshRuntimeStatus()
            }
        }
    }

    // MARK: - Settings

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        persist()
        let snapshot = settings
        let identity = monitor.currentIdentity
        Task {
            if paused {
                await driver.send(.pause)
            } else {
                await driver.send(.resume(identity))
            }
            await driver.update(settings: snapshot)
            await refreshRuntimeStatus()
        }
    }

    func applyNow() {
        guard !settings.paused else { return }
        Task {
            await driver.send(.resume(monitor.currentIdentity))
            try? await Task.sleep(for: .milliseconds(400))
            await refreshRuntimeStatus()
            refreshEffectiveProxy()
        }
    }

    func setEndpoint(host: String, portText: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let port = Int(portText),
              (1...65535).contains(port) else { return false }
        settings.endpoint = ProxyEndpoint(host: trimmed, port: port)
        persist()
        syncDriver()
        endpointReachable = nil
        refreshEndpointReachability()
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            lastError = error.localizedDescription
        }
        refreshLoginItemStatus()
        persist()
    }

    func requestLocationAccess() {
        locationService.requestAuthorization()
        Task {
            try? await Task.sleep(for: .seconds(1))
            locationAuthorized = locationService.isAuthorized
        }
    }

    func requestNotificationAccess() {
        Task {
            notificationAuthorized = await notificationService.requestAuthorization()
        }
    }

    // MARK: - Rules

    func addRule(_ rule: Rule) {
        if rule.place != nil {
            settings.rules.insertByPriority(rule)
        } else {
            settings.rules.append(rule)
        }
        persist()
        syncDriver()
    }

    func updateRule(_ rule: Rule) {
        guard let index = settings.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        settings.rules[index] = rule
        persist()
        syncDriver()
    }

    func setRuleEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = settings.rules.firstIndex(where: { $0.id == id }) else { return }
        settings.rules[index].enabled = enabled
        persist()
        syncDriver()
    }

    func deleteRule(id: UUID) {
        settings.rules.removeAll { $0.id == id }
        persist()
        syncDriver()
    }

    func deleteRules(at offsets: IndexSet) {
        settings.rules.remove(atOffsets: offsets)
        persist()
        syncDriver()
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        settings.rules.move(fromOffsets: source, toOffset: destination)
        persist()
        syncDriver()
    }

    func moveRule(id: UUID, offset: Int) {
        guard let index = settings.rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard settings.rules.indices.contains(target) else { return }
        settings.rules.swapAt(index, target)
        persist()
        syncDriver()
    }

    // MARK: - Helpers

    func refreshServices() {
        availableServices = (try? setup.services()) ?? []
    }

    func refreshEffectiveProxy() {
        effectiveProxy = SystemNetwork.effectiveProxy()
    }

    /// 端点探测会阻塞，放到后台线程，避免卡住界面。
    func refreshEndpointReachability() {
        let endpoint = settings.endpoint
        Task.detached { [weak self] in
            let reachable = TCPEndpointProbe().isReachable(endpoint, timeout: 1.0)
            await MainActor.run {
                self?.endpointReachable = reachable
            }
        }
    }

    func refreshNetwork() {
        monitor.refresh()
        currentNetwork = monitor.currentIdentity
        refreshServices()
        refreshWiFiNetworks()
    }

    /// 读取系统保存过的 Wi-Fi 名称（当前连接优先，其次为曾经连接/加入过的网络）。
    func refreshWiFiNetworks() {
        guard let device = NetworkMonitor.wifiInterfaceName() else {
            knownWiFiNetworks = []
            return
        }
        var names: [String] = []
        if let current = try? setup.currentWirelessNetwork(interfaceName: device),
           !current.isEmpty {
            names.append(current)
        }
        if let ssid = currentNetwork?.ssid, !ssid.isEmpty {
            names.append(ssid)
        }
        names += (try? setup.preferredWirelessNetworks(interfaceName: device)) ?? []

        var seen = Set<String>()
        knownWiFiNetworks = names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func refreshLoginItemStatus() {
        loginItemStatus = LoginItemService.statusText
    }

    private func persist() {
        do {
            try store.save(settings)
        } catch {
            lastError = "保存设置失败：\(error.localizedDescription)"
        }
    }

    private func syncDriver() {
        let snapshot = settings
        Task { await driver.update(settings: snapshot) }
    }
}
