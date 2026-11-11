import AppKit
import SwiftUI
import WorkProxyCore

// MARK: - Rule draft

enum RuleNetworkKind: String, CaseIterable, Hashable {
    case wifi
    case wired
}

struct RuleDraft {
    var name = ""
    var networkKind: RuleNetworkKind = .wifi
    var ssid = ""
    var interfaceName = ""
    var action: ProxyAction = .on
    var enabled = true
    var usePlace = false
    var placeLabel = ""
    var placeAddress: String?
    var latitude = 0.0
    var longitude = 0.0
    var radius = 500.0
    var hasPlaceCoordinates = false

    init(rule: Rule?, currentNetwork: NetworkIdentity?) {
        guard let rule else {
            if let network = currentNetwork {
                switch network.kind {
                case .wifi:
                    networkKind = .wifi
                    ssid = network.ssid ?? ""
                case .wired:
                    networkKind = .wired
                    interfaceName = network.interfaceName
                case .other:
                    break
                }
            }
            return
        }
        name = rule.name
        action = rule.action
        enabled = rule.enabled
        switch rule.network {
        case let .wifi(value):
            networkKind = .wifi
            ssid = value
        case let .wired(value):
            networkKind = .wired
            interfaceName = value
        }
        if let place = rule.place {
            usePlace = true
            placeLabel = place.label
            placeAddress = place.address
            latitude = place.latitude
            longitude = place.longitude
            radius = place.radiusMeters
            hasPlaceCoordinates = true
        }
    }

    func makeRule(id: UUID) -> Rule? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let network: RuleNetwork
        switch networkKind {
        case .wifi:
            let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            network = .wifi(ssid: value)
        case .wired:
            guard !interfaceName.isEmpty else { return nil }
            network = .wired(interfaceName: interfaceName)
        }

        let place: PlaceCondition?
        if usePlace {
            guard hasPlaceCoordinates else { return nil }
            place = PlaceCondition(
                label: placeLabel.isEmpty ? "地点" : placeLabel,
                address: placeAddress,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: radius
            )
        } else {
            place = nil
        }

        return Rule(id: id, name: trimmedName, network: network,
                    place: place, action: action, enabled: enabled)
    }
}

private extension String {
    var trimmedForInput: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared UI

struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Rule editor

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: Rule?
    let services: [NetworkService]
    let currentNetwork: NetworkIdentity?
    let knownWiFiNetworks: [String]
    let onRefreshWiFi: () -> Void
    @ObservedObject var locationService: LocationService
    let onSave: (Rule) -> Void

    @State private var draft: RuleDraft
    @State private var manualWiFi: Bool
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searchError: String?
    @FocusState private var nameFocused: Bool

    init(existing: Rule?, services: [NetworkService],
         currentNetwork: NetworkIdentity?, knownWiFiNetworks: [String],
         locationService: LocationService,
         onRefreshWiFi: @escaping () -> Void,
         onSave: @escaping (Rule) -> Void) {
        let initial = RuleDraft(rule: existing, currentNetwork: currentNetwork)
        self.existing = existing
        self.services = services
        self.currentNetwork = currentNetwork
        self.knownWiFiNetworks = knownWiFiNetworks
        self.onRefreshWiFi = onRefreshWiFi
        _locationService = ObservedObject(wrappedValue: locationService)
        self.onSave = onSave
        _draft = State(initialValue: initial)
        _manualWiFi = State(initialValue: initial.networkKind == .wifi
            && (knownWiFiNetworks.isEmpty
                || (!initial.ssid.isEmpty && !knownWiFiNetworks.contains(initial.ssid))))
    }

    private var wiredServices: [NetworkService] {
        services.filter { $0.device != nil && $0.name != "Wi-Fi" }
    }

    /// 下拉选项：保存过的网络 + 正在编辑但不在列表中的名称。
    private var wifiOptions: [String] {
        var values = knownWiFiNetworks
        let current = draft.ssid.trimmedForInput
        if !current.isEmpty, !values.contains(current) {
            values.insert(current, at: 0)
        }
        return values
    }

    private var isValid: Bool {
        draft.makeRule(id: existing?.id ?? UUID()) != nil
    }

    private var title: String {
        existing == nil ? "添加规则" : "编辑规则"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text("网络条件命中后，自动切换系统代理。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    TextField("名称", text: $draft.name)
                        .focused($nameFocused)
                    Toggle("启用", isOn: $draft.enabled)
                } header: {
                    Text("规则")
                } footer: {
                    if draft.name.trimmedForInput.isEmpty {
                        Text("名称为必填项。")
                    }
                }

                Section {
                    Picker("类型", selection: $draft.networkKind) {
                        Text("Wi-Fi").tag(RuleNetworkKind.wifi)
                        Text("有线").tag(RuleNetworkKind.wired)
                    }
                    .pickerStyle(.segmented)

                    if draft.networkKind == .wifi {
                        wifiEditor
                    } else {
                        Picker("接口", selection: $draft.interfaceName) {
                            Text("请选择").tag("")
                            ForEach(wiredServices) { service in
                                Text("\(service.name) (\(service.device ?? "?"))")
                                    .tag(service.device ?? "")
                            }
                        }
                        if draft.interfaceName.isEmpty {
                            Text("请选择要匹配的有线接口。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("网络条件")
                } footer: {
                    Text("跟随系统当前的主要物理连接匹配；有线规则按接口判断。")
                }

                Section {
                    Toggle("只在指定地点生效", isOn: $draft.usePlace.animation())
                    if draft.usePlace {
                        placeEditor
                    }
                } header: {
                    Text("地点条件（可选）")
                } footer: {
                    Text("地点是附加条件：网络与地点同时满足时规则才会命中。")
                }

                Section("动作") {
                    Picker("动作", selection: $draft.action) {
                        ForEach(ProxyAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(16)
        }
        .frame(width: 580, height: 700)
        .onAppear {
            if existing == nil { nameFocused = true }
        }
    }

    @ViewBuilder
    private var wifiEditor: some View {
        if manualWiFi {
            TextField("Wi-Fi 名称（SSID）", text: $draft.ssid)
            HStack {
                Button("从列表选择") {
                    manualWiFi = false
                    if draft.ssid.isEmpty, currentNetwork?.kind == .wifi,
                       let ssid = currentNetwork?.ssid {
                        draft.ssid = ssid
                    }
                }
                .disabled(knownWiFiNetworks.isEmpty)
                Button("刷新列表") { onRefreshWiFi() }
                Spacer()
                if !locationService.isAuthorized {
                    Button("允许定位") { locationService.requestAuthorization() }
                        .help("读取当前 Wi-Fi 名称需要定位权限")
                }
            }
        } else {
            Picker("Wi-Fi 名称", selection: $draft.ssid) {
                Text("请选择").tag("")
                ForEach(wifiOptions, id: \.self) { ssid in
                    Text(ssid).tag(ssid)
                }
            }
            HStack {
                Button("手动输入") {
                    manualWiFi = true
                    if let ssid = currentNetwork?.ssid, draft.ssid.isEmpty {
                        draft.ssid = ssid
                    }
                }
                Button("刷新列表") { onRefreshWiFi() }
                Spacer()
                if !locationService.isAuthorized {
                    Button("允许定位") { locationService.requestAuthorization() }
                        .help("读取当前 Wi-Fi 名称需要定位权限")
                }
            }
            if knownWiFiNetworks.isEmpty {
                Text("没有读取到已保存的 Wi-Fi，请手动输入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if draft.ssid.isEmpty {
                Text("请选择当前或曾经连接过的 Wi-Fi。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var placeEditor: some View {
        HStack {
            TextField("搜索地址", text: $query)
                .onSubmit { search() }
            Button("搜索") { search() }
                .disabled(query.trimmedForInput.isEmpty || searching)
        }

        if searching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在搜索…").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let searchError {
            Text(searchError).font(.caption).foregroundStyle(.red)
        }

        ForEach(results) { candidate in
            Button {
                select(candidate)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected(candidate) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected(candidate) ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.label)
                        if let address = candidate.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        if draft.hasPlaceCoordinates {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.placeLabel.isEmpty ? "已选择地点" : draft.placeLabel)
                        .font(.body.weight(.medium))
                    if let address = draft.placeAddress {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("清除") {
                    draft.hasPlaceCoordinates = false
                    draft.placeLabel = ""
                    draft.placeAddress = nil
                }
                .buttonStyle(.borderless)
            }
        }

        TextField("地点名称", text: $draft.placeLabel)
            .disabled(!draft.hasPlaceCoordinates)

        LabeledContent("范围") {
            HStack(spacing: 10) {
                Slider(value: $draft.radius, in: 100...5000, step: 50)
                    .frame(minWidth: 160)
                Text("\(Int(draft.radius)) 米")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                Menu {
                    ForEach([100.0, 300.0, 500.0, 1000.0, 3000.0], id: \.self) { value in
                        Button("\(Int(value)) 米") { draft.radius = value }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }

        if !draft.hasPlaceCoordinates {
            Text("请先搜索并选择地点。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func isSelected(_ candidate: PlaceCandidate) -> Bool {
        draft.hasPlaceCoordinates
            && abs(draft.latitude - candidate.latitude) < 0.000001
            && abs(draft.longitude - candidate.longitude) < 0.000001
    }

    private func save() {
        guard let rule = draft.makeRule(id: existing?.id ?? UUID()) else { return }
        onSave(rule)
        dismiss()
    }

    private func search() {
        let text = query.trimmedForInput
        guard !text.isEmpty else { return }
        searching = true
        searchError = nil
        Task {
            defer { searching = false }
            do {
                results = try await locationService.searchAddress(text)
                if results.isEmpty { searchError = "没有找到结果。" }
            } catch {
                searchError = error.localizedDescription
            }
        }
    }

    private func select(_ candidate: PlaceCandidate) {
        draft.latitude = candidate.latitude
        draft.longitude = candidate.longitude
        draft.placeLabel = candidate.label
        draft.placeAddress = candidate.address
        draft.hasPlaceCoordinates = true
    }
}

// MARK: - Rule row

struct RuleRow: View {
    @ObservedObject var model: AppModel
    let rule: Rule

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("拖动排序")

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(rule.id, $0) }
            ))
            .labelsHidden()
            .accessibilityLabel("启用规则 \(rule.name)")

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                HStack(spacing: 6) {
                    Image(systemName: networkIcon)
                    Text(networkDescription)
                    Text("·")
                    Text(rule.action.displayName)
                    if let place = rule.place {
                        Text("·")
                        Text("\(place.label) · \(Int(place.radiusMeters)) 米")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .opacity(rule.enabled ? 1 : 0.6)

            Spacer()

            if hovering {
                Button {
                    model.editingRule = RuleEditorTarget(rule: rule)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑规则")
                .accessibilityLabel("编辑规则 \(rule.name)")

                Button(role: .destructive) {
                    model.deleteRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除规则")
                .accessibilityLabel("删除规则 \(rule.name)")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("编辑") {
                model.editingRule = RuleEditorTarget(rule: rule)
            }
            Button("复制") {
                model.addRule(Rule(
                    name: "\(rule.name) 副本",
                    network: rule.network,
                    place: rule.place,
                    action: rule.action,
                    enabled: rule.enabled
                ))
            }
            Divider()
            Button(rule.enabled ? "停用" : "启用") {
                model.setRuleEnabled(rule.id, !rule.enabled)
            }
            Button("上移") { model.moveRule(id: rule.id, offset: -1) }
            Button("下移") { model.moveRule(id: rule.id, offset: 1) }
            Divider()
            Button("删除", role: .destructive) {
                model.deleteRule(id: rule.id)
            }
        }
    }

    private var networkIcon: String {
        switch rule.network {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        }
    }

    private var networkDescription: String {
        switch rule.network {
        case let .wifi(ssid):
            return ssid
        case let .wired(interfaceName):
            return model.availableServices
                .first { $0.device == interfaceName }?.name ?? interfaceName
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var model: AppModel
    let onAddRule: () -> Void
    let onShowRules: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                if needsLocationHint {
                    locationHint
                }
                detailsCard
                if let error = model.lastError {
                    errorBanner(error)
                }
                actionRow
                if model.settings.rules.isEmpty {
                    emptyRulesCard
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshEffectiveProxy()
            model.refreshEndpointReachability()
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: model.menuBarIcon)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusTint)
                .frame(width: 46, height: 46)
                .background(statusTint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(model.currentNetworkDescription)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 7) {
                    StatusDot(color: proxyColor)
                    Text(model.systemProxySummary)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            StatusBadge(text: stateBadgeText,
                        systemImage: stateBadgeIcon,
                        tint: stateBadgeTint)
        }
        .padding(20)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
        }
    }

    private var needsLocationHint: Bool {
        model.currentNetwork?.kind == .wifi
            && model.currentNetwork?.ssid == nil
            && !model.locationAuthorized
    }

    private var locationHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("无法读取 Wi-Fi 名称").font(.callout.weight(.medium))
                Text("Wi-Fi 规则需要定位权限才能匹配当前网络名称。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("允许定位") { model.requestLocationAccess() }
            Button("打开设置") { onShowSettings() }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detailsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                detailLine(icon: "point.3.connected.trianglepath.dotted", title: "代理端点") {
                    HStack(spacing: 7) {
                        Text(model.settings.endpoint.display)
                            .monospacedDigit()
                        StatusDot(color: endpointColor)
                        Text(model.endpointStatusText)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.vertical, 8)
                detailLine(icon: "clock.arrow.circlepath", title: "最近状态") {
                    Text(model.statusText).foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 8)
                detailLine(icon: "list.bullet.rectangle", title: "规则") {
                    Text("\(model.settings.rules.count) 条，启用 \(model.enabledRuleCount) 条")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("管理规则") { onShowRules() }
                        .buttonStyle(.borderless)
                }
            }
            .padding(8)
        } label: {
            Label("状态详情", systemImage: "info.circle")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                model.applyNow()
            } label: {
                Label("立即应用", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPaused)

            Button {
                onAddRule()
            } label: {
                Label("添加规则", systemImage: "plus")
            }

            Spacer()

            Toggle("暂停自动切换", isOn: Binding(
                get: { model.isPaused },
                set: { model.setPaused($0) }
            ))
            .toggleStyle(.switch)
        }
    }

    private var emptyRulesCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 30, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("还没有规则").font(.headline)
                Text("连接网络后添加第一条规则，workProxy 会在网络稳定 3 秒后自动执行。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("添加规则") { onAddRule() }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(.quaternary.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("执行失败").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func detailLine<Content: View>(
        icon: String, title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
    }

    private var statusTint: Color {
        if model.lastError != nil { return .orange }
        if model.isPaused { return .orange }
        switch model.systemProxyState {
        case .on: return .green
        case .off: return .secondary
        case .mixed: return .orange
        case .unknown: return .secondary
        }
    }

    private var proxyColor: Color {
        switch model.systemProxyState {
        case .on: return .green
        case .off: return .secondary
        case .mixed: return .orange
        case .unknown: return .secondary
        }
    }

    private var endpointColor: Color {
        switch model.endpointReachable {
        case true: return .green
        case false: return .red
        case nil: return .secondary
        }
    }

    private var stateBadgeText: String {
        if model.lastError != nil { return "执行失败" }
        return model.isPaused ? "已暂停" : "自动切换中"
    }

    private var stateBadgeIcon: String {
        if model.lastError != nil { return "exclamationmark.circle.fill" }
        return model.isPaused ? "pause.circle.fill" : "checkmark.circle.fill"
    }

    private var stateBadgeTint: Color {
        if model.lastError != nil { return .orange }
        return model.isPaused ? .orange : .green
    }
}

// MARK: - Rules

struct RulesView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmedForInput.isEmpty
    }

    private var filteredRules: [Rule] {
        let text = query.trimmedForInput
        guard !text.isEmpty else { return model.settings.rules }
        return model.settings.rules.filter { rule in
            if rule.name.localizedCaseInsensitiveContains(text) { return true }
            switch rule.network {
            case let .wifi(ssid):
                return ssid.localizedCaseInsensitiveContains(text)
            case let .wired(interfaceName):
                let service = model.availableServices
                    .first { $0.device == interfaceName }?.name ?? interfaceName
                return service.localizedCaseInsensitiveContains(text)
                    || interfaceName.localizedCaseInsensitiveContains(text)
            }
        }
    }

    var body: some View {
        Group {
            if model.settings.rules.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: "还没有规则",
                    message: "规则按从上到下的顺序匹配。连接目标网络后，workProxy 会自动切换系统代理。",
                    actionTitle: "添加规则"
                ) {
                    model.editingRule = RuleEditorTarget(rule: nil)
                }
            } else {
                List {
                    Section {
                        ForEach(filteredRules) { rule in
                            RuleRow(model: model, rule: rule)
                        }
                        .onMove(perform: isSearching ? nil : { source, destination in
                            model.moveRules(from: source, to: destination)
                        })
                    } header: {
                        Text("从上到下匹配，第一条命中的规则生效")
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if filteredRules.isEmpty {
                        Text("没有匹配的规则")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("规则")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.editingRule = RuleEditorTarget(rule: nil)
                } label: {
                    Label("添加规则", systemImage: "plus")
                }
                .help("添加规则（⌘N）")
            }
            ToolbarItem {
                Button {
                    model.refreshNetwork()
                } label: {
                    Label("刷新网络", systemImage: "arrow.clockwise")
                }
                .help("刷新网络（⌘R）")
            }
        }
        .searchable(text: $query, prompt: "搜索名称、Wi-Fi 或接口")
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @ObservedObject var model: AppModel

    @State private var endpointHost: String
    @State private var endpointPort: String
    @State private var endpointError: String?

    init(model: AppModel) {
        self.model = model
        _endpointHost = State(initialValue: model.settings.endpoint.host)
        _endpointPort = State(initialValue: String(model.settings.endpoint.port))
    }

    var body: some View {
        Form {
            Section("代理") {
                LabeledContent("代理端点") {
                    HStack(spacing: 6) {
                        TextField("127.0.0.1", text: $endpointHost)
                            .labelsHidden()
                            .frame(width: 140)
                        Text(":")
                        TextField("7897", text: $endpointPort)
                            .labelsHidden()
                            .monospacedDigit()
                            .frame(width: 70)
                        Button("保存") { saveEndpoint() }
                    }
                }

                LabeledContent("连接状态") {
                    HStack(spacing: 7) {
                        StatusDot(color: endpointColor)
                        Text(model.endpointStatusText)
                        Button("重新检测") { model.refreshEndpointReachability() }
                            .buttonStyle(.borderless)
                    }
                }

                if let endpointError {
                    Text(endpointError).font(.caption).foregroundStyle(.red)
                }

                Text("开启系统代理前会先检查该端口；不可连接时不会写入系统代理，避免断网。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动切换") {
                Toggle("暂停自动切换", isOn: Binding(
                    get: { model.isPaused },
                    set: { model.setPaused($0) }
                ))
                Toggle("登录时启动", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                LabeledContent("登录项") {
                    Text(model.loginItemStatus).foregroundStyle(.secondary)
                }
            }

            Section("权限") {
                permissionRow(
                    title: "定位",
                    granted: model.locationAuthorized,
                    detail: "读取 Wi-Fi 名称与判断地点",
                    request: { model.requestLocationAccess() },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                )
                permissionRow(
                    title: "通知",
                    granted: model.notificationAuthorized,
                    detail: "仅在执行失败时通知一次",
                    request: { model.requestNotificationAccess() },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.notifications"
                )
            }

            Section("数据") {
                LabeledContent("设置文件") {
                    HStack {
                        Text(JSONSettingsStore.defaultURL().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [JSONSettingsStore.defaultURL()]
                            )
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }

    private func permissionRow(
        title: String, granted: Bool, detail: String,
        request: @escaping () -> Void, settingsURL: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                StatusBadge(
                    text: granted ? "已授权" : "未授权",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle",
                    tint: granted ? .green : .orange
                )
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if !granted {
                    Button("请求", action: request)
                }
                Button("系统设置") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var endpointColor: Color {
        switch model.endpointReachable {
        case true: return .green
        case false: return .red
        case nil: return .secondary
        }
    }

    private func saveEndpoint() {
        if model.setEndpoint(host: endpointHost, portText: endpointPort) {
            endpointError = nil
        } else {
            endpointError = "格式无效：主机不能为空，端口需在 1–65535 之间。"
        }
    }
}

// MARK: - About

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("workProxy").font(.largeTitle.bold())
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("按网络与地点规则自动开关 macOS 系统代理。")
                .foregroundStyle(.secondary)

            Divider().frame(width: 260).padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Label("只操作系统代理，不控制 TUN 模式", systemImage: "checkmark.shield")
                Label("规则命中后直接读写系统代理设置", systemImage: "slider.horizontal.3")
                Label("客户端未监听端口时拒绝开启，避免断网", systemImage: "bolt.slash")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Link("GitHub 仓库", destination: URL(string: "https://github.com/sawyerfeng/workProxy")!)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .navigationTitle("关于")
    }
}

// MARK: - Root

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case rules
    case preferences
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .rules: return "规则"
        case .preferences: return "设置"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "network"
        case .rules: return "list.bullet.rectangle"
        case .preferences: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SidebarSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detail
        }
        .navigationTitle((selection ?? .overview).title)
        .frame(minWidth: 820, minHeight: 560)
        .sheet(item: $model.editingRule) { target in
            RuleEditorView(
                existing: target.rule,
                services: model.availableServices,
                currentNetwork: model.currentNetwork,
                knownWiFiNetworks: model.knownWiFiNetworks,
                locationService: model.locationService,
                onRefreshWiFi: { model.refreshWiFiNetworks() }
            ) { rule in
                if target.rule == nil {
                    model.addRule(rule)
                } else {
                    model.updateRule(rule)
                }
                model.editingRule = nil
            }
        }
        .onAppear { model.start() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(
                model: model,
                onAddRule: { model.editingRule = RuleEditorTarget(rule: nil) },
                onShowRules: { selection = .rules },
                onShowSettings: { selection = .preferences }
            )
        case .rules:
            RulesView(model: model)
        case .preferences:
            PreferencesView(model: model)
        case .about:
            AboutView()
        }
    }
}

// MARK: - Menu bar

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.currentNetworkDescription)
        Text(model.systemProxySummary)
        if let error = model.lastError {
            Text(error)
        }
        Divider()
        Button {
            model.applyNow()
        } label: {
            Label("立即应用", systemImage: "bolt.fill")
        }
        .disabled(model.isPaused)
        Button {
            model.setPaused(!model.isPaused)
        } label: {
            Label(model.isPaused ? "恢复自动切换" : "暂停自动切换",
                  systemImage: model.isPaused ? "play.circle" : "pause.circle")
        }
        Divider()
        Button {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("打开设置…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出 workProxy", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - Commands

@MainActor
struct WorkProxyCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("添加规则") {
                openWindow(id: "settings")
                model.editingRule = RuleEditorTarget(rule: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .toolbar) {
            Button("立即应用") { model.applyNow() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isPaused)
            Button("刷新网络") { model.refreshNetwork() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - App

struct WorkProxyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("workProxy", id: "settings") {
            RootView(model: model)
                .onAppear { model.start() }
        }
        .defaultSize(width: 880, height: 620)
        .windowResizability(.contentMinSize)
        .commands { WorkProxyCommands(model: model) }

        MenuBarExtra("workProxy", systemImage: model.menuBarIcon) {
            MenuContent(model: model)
                .onAppear { model.start() }
        }
    }
}

// MARK: - Entry point

@main
enum EntryPoint {
    @MainActor
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.contains("--status") {
            exit(runStatus())
        }
        if arguments.contains("--on") {
            exit(runApply(true, arguments: arguments))
        }
        if arguments.contains("--off") {
            exit(runApply(false, arguments: arguments))
        }
        if arguments.contains("--wifi-networks") {
            exit(runWiFiNetworks())
        }
        WorkProxyApp.main()
    }

    @MainActor
    private static func runStatus() -> Int32 {
        let setup = Networksetup()
        do {
            let snapshot = try SystemSnapshot.capture(setup: setup,
                                                      message: "只读探测；未修改系统代理。")
            print(snapshot.report.json)
            return 0
        } catch {
            print("无法读取系统代理：\(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func runApply(_ enabled: Bool, arguments: [String]) -> Int32 {
        let setup = Networksetup()
        do {
            let endpoint = try parseEndpoint(arguments)
            let services = try setup.services()
            let states = try SystemProxyController(setup: setup)
                .apply(enabled, endpoint: endpoint, to: services)
            let snapshot = try SystemSnapshot.capture(
                setup: setup,
                message: "已对 \(states.count) 个服务\(enabled ? "开启" : "关闭")系统代理。"
            )
            print(snapshot.report.json)
            return 0
        } catch {
            print("执行失败：\(error.localizedDescription)")
            return 1
        }
    }

    @MainActor
    private static func runWiFiNetworks() -> Int32 {
        guard let device = NetworkMonitor.wifiInterfaceName() else {
            print("找不到 Wi-Fi 接口。")
            return 1
        }
        let setup = Networksetup()
        var names: [String] = []
        if let current = try? setup.currentWirelessNetwork(interfaceName: device) {
            names.append(current)
        }
        names += (try? setup.preferredWirelessNetworks(interfaceName: device)) ?? []

        var seen = Set<String>()
        for name in names where !name.isEmpty && seen.insert(name).inserted {
            print(name)
        }
        return 0
    }

    private static func parseEndpoint(_ arguments: [String]) throws -> ProxyEndpoint {
        guard let index = arguments.firstIndex(of: "--endpoint"),
              index + 1 < arguments.count else {
            return ProxyEndpoint()
        }
        let text = arguments[index + 1]
        guard let colon = text.lastIndex(of: ":") else {
            throw ProbeError.message("--endpoint 格式应为 host:port。")
        }
        let host = String(text[..<colon])
        let portText = String(text[text.index(after: colon)...])
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            throw ProbeError.message("--endpoint 格式应为 host:port，端口范围 1–65535。")
        }
        return ProxyEndpoint(host: host, port: port)
    }
}

enum ProbeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text): return text
        }
    }
}
