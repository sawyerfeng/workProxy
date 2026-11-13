import AppKit
import MapKit
import SwiftUI
import WorkProxyCore

private extension String {
    var trimmedForInput: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Shared UI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ruleSketch(icon: "building.2", action: .off)
                ruleSketch(icon: "house", action: .on)
            }
            .padding(.bottom, 6)
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.text)
            Button(action: action) {
                Label(actionTitle, systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(scheme == .dark ? Brand.ink : .white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(palette.mint, in: Capsule())
            }
            .buttonStyle(PressFeedbackStyle())
            .help(message)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    /// 示意两条典型规则：公司网络关闭代理，家里开启代理。
    private func ruleSketch(icon: String, action: ProxyAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.secondary)
            RouteArrow(direction: action == .on ? .outbound : .inbound)
                .stroke(palette.actionColor(action),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1) }
        .rotationEffect(.degrees(action == .on ? 3 : -3))
        .accessibilityHidden(true)
    }
}

struct LocationAccessHint: View {
    @ObservedObject var service: LocationService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.slash").foregroundStyle(.orange)
            Text("读取 Wi-Fi 需要定位权限").font(.callout.weight(.medium))
            Spacer()
            if service.authorizationStatus == .notDetermined {
                Button("允许定位") { service.requestAuthorization() }
            } else {
                Button("系统设置") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
        }
    }
}

// MARK: - Rule editor

struct RuleEditorView: View {
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    @Environment(\.dismiss) private var dismiss

    let existing: Rule?
    let services: [NetworkService]
    let currentNetwork: NetworkIdentity?
    let knownWiFiNetworks: [String]
    let onRefreshWiFi: () -> Void
    @ObservedObject var locationService: LocationService
    let onSave: (Rule) -> String?

    @State private var draft: RuleDraft
    @State private var manualWiFi: Bool
    @State private var query = ""
    @State private var results: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searchError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNetworkOptions: Bool
    @State private var saveError: String?

    init(existing: Rule?, services: [NetworkService],
         currentNetwork: NetworkIdentity?, knownWiFiNetworks: [String],
         locationService: LocationService,
         onRefreshWiFi: @escaping () -> Void,
         onSave: @escaping (Rule) -> String?) {
        let initial = RuleDraft(rule: existing, currentNetwork: currentNetwork)
        self.existing = existing
        self.services = services
        self.currentNetwork = currentNetwork
        self.knownWiFiNetworks = knownWiFiNetworks
        self.onRefreshWiFi = onRefreshWiFi
        _locationService = ObservedObject(wrappedValue: locationService)
        self.onSave = onSave
        _draft = State(initialValue: initial)
        _showNetworkOptions = State(initialValue: initial.makeRule(id: UUID()) == nil)
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

    private var selectedNetworkName: String {
        if draft.networkKind == .wifi {
            return draft.ssid.trimmedForInput.isEmpty ? "选择 Wi-Fi" : draft.ssid.trimmedForInput
        }
        return services.first { $0.device == draft.interfaceName }?.name
            ?? (draft.interfaceName.isEmpty ? "选择有线网络" : draft.interfaceName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandBadge(size: 32, state: RouteState(draft.action == .on ? .on : .off))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.text)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("连接网络").font(.headline)
                        HStack(spacing: 12) {
                            Image(systemName: draft.networkKind == .wifi ? "wifi" : "cable.connector")
                                .font(.title3).foregroundStyle(.tint)
                            Text(selectedNetworkName).fontWeight(.medium)
                                .lineLimit(2).textSelection(.enabled)
                            Spacer()
                            Button(showNetworkOptions ? "收起" : "更换网络") {
                                showNetworkOptions.toggle()
                            }
                            .buttonStyle(.borderless)
                        }
                        if showNetworkOptions {
                            Picker("网络类型", selection: $draft.networkKind) {
                                Text("Wi-Fi").tag(RuleNetworkKind.wifi)
                                Text("有线").tag(RuleNetworkKind.wired)
                            }
                            .pickerStyle(.segmented)
                            if draft.networkKind == .wifi {
                                wifiEditor
                            } else {
                                Picker("有线网络", selection: $draft.interfaceName) {
                                    Text("请选择").tag("")
                                    ForEach(wiredServices) { service in
                                        Text(service.name).tag(service.device ?? "")
                                    }
                                    if !draft.interfaceName.isEmpty,
                                       !wiredServices.contains(where: { $0.device == draft.interfaceName }) {
                                        Text("\(draft.interfaceName)（当前不可用）").tag(draft.interfaceName)
                                    }
                                }
                                if draft.interfaceName.isEmpty {
                                    Text("请选择有线网络；未发现时请连接网卡后刷新。")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("刷新网络", action: onRefreshWiFi)
                                }
                            }
                        }
                        if draft.networkKind == .wifi && !locationService.isAuthorized {
                            LocationAccessHint(service: locationService)
                        }
                        if draft.networkKind == .wifi && draft.ssid.trimmedForInput.isEmpty && !showNetworkOptions {
                            Text("未读取到当前 Wi-Fi 名称，请选择网络或手动输入。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("自动执行").font(.headline)
                        ProxyActionChoices(selection: $draft.action)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $draft.usePlace) {
                            Text("限定生效地点（可选）").font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.switch).controlSize(.small)
                        if draft.usePlace {
                            if draft.networkKind != .wifi && !locationService.isAuthorized {
                                LocationAccessHint(service: locationService)
                            }
                            Divider()
                            placeEditor
                        }
                    }
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .frame(height: draft.usePlace ? 440 : (showNetworkOptions ? 340 : 260))

            Divider()
            HStack {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存规则") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.mint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(palette.canvas)
        .tint(palette.mint)
        .frame(width: 520)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showNetworkOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: draft.usePlace)
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
            TextField("搜索地址", text: $query, prompt: Text("输入公司、小区或街道地址"))
                .textFieldStyle(.roundedBorder)
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
            Map(coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude),
                latitudinalMeters: draft.radius * 3,
                longitudinalMeters: draft.radius * 3
            )), interactionModes: [], annotationItems: [
                PlaceCandidate(label: draft.placeLabel, address: draft.placeAddress,
                               latitude: draft.latitude, longitude: draft.longitude)
            ]) { place in
                MapMarker(coordinate: CLLocationCoordinate2D(
                    latitude: place.latitude, longitude: place.longitude), tint: .mint)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("所选地点地图：\(draft.placeLabel)")

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
                .help("选择常用范围")
                .accessibilityLabel("选择常用范围")
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
        saveError = onSave(rule)
        if saveError == nil { dismiss() }
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
        results = []
    }
}

// MARK: - Rule row

struct RuleRow: View {
    @ObservedObject var model: AppModel
    let rule: Rule
    let priority: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    private var accent: Color { palette.actionColor(rule.action) }
    private var isActive: Bool { rule.enabled && !model.isPaused && model.activeRuleID == rule.id }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(priority)")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(palette.secondary)
                .frame(width: 18)
                .accessibilityLabel("优先级 \(priority)")
            Image(systemName: networkIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(rule.enabled ? palette.text : palette.secondary)
                .frame(width: 40, height: 40)
                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(networkKindLabel)
                .help(networkKindLabel)
            HStack(spacing: 8) {
                Text(networkDescription)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(networkDescription)
                if isActive {
                    ActiveRuleBadge(color: palette.mint)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .opacity(rule.enabled ? 1 : 0.5)
            RouteArrow(direction: rule.action == .on ? .outbound : .inbound)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 17, height: 17)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .opacity(rule.enabled ? 1 : 0.5)
                .accessibilityLabel(rule.action.displayName)
                .help("匹配这个网络时，\(rule.action.displayName)")
            Image(systemName: rule.place == nil ? "location.slash" : "location.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(rule.place == nil ? palette.secondary : palette.mint)
                .frame(width: 34, height: 34)
                .background((rule.place == nil ? palette.line : palette.mint.opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .opacity(rule.enabled ? 1 : 0.5)
                .accessibilityLabel(locationDescription)
                .help(locationDescription)
            Button {
                model.editingRule = RuleEditorTarget(rule: rule)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 26, height: 26)
                    .background(palette.canvas, in: Circle())
            }
            .buttonStyle(PressFeedbackStyle())
            .opacity(hovering ? 1 : 0)
            .help("编辑规则")
            .accessibilityLabel("编辑规则 \(networkDescription)")
            Toggle("启用规则 \(networkDescription)", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(rule.id, $0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(palette.mint)
        }
        .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? palette.mint.opacity(0.55) : (hovering ? palette.text.opacity(0.16) : palette.line),
                        lineWidth: 1)
        }
        .shadow(color: .black.opacity(hovering ? (scheme == .dark ? 0.25 : 0.07) : 0), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(count: 2) { model.editingRule = RuleEditorTarget(rule: rule) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.75), value: rule.enabled)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: isActive)
        .contextMenu {
            Button("编辑") { model.editingRule = RuleEditorTarget(rule: rule) }
            Button("复制") {
                model.addRule(Rule(name: rule.network.displayName, network: rule.network,
                                   place: rule.place, action: rule.action, enabled: rule.enabled))
            }
            Divider()
            Button(rule.enabled ? "停用" : "启用") {
                model.setRuleEnabled(rule.id, !rule.enabled)
            }
            Button("上移") { model.moveRule(id: rule.id, offset: -1) }
            Button("下移") { model.moveRule(id: rule.id, offset: 1) }
            Divider()
            Button("删除", role: .destructive) { model.deleteRule(id: rule.id) }
        }
    }

    private var locationDescription: String {
        guard let place = rule.place else { return "不限地点" }
        return "已启用地点：\(place.label) · \(Int(place.radiusMeters)) 米内"
    }

    private var networkKindLabel: String {
        switch rule.network {
        case .wifi: return "Wi-Fi"
        case .wired: return "有线网络"
        }
    }

    private var networkIcon: String {
        switch rule.network {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        }
    }

    private var networkDescription: String { model.networkName(for: rule.network) }
}

/// 标记最近一次自动匹配命中的规则。
private struct ActiveRuleBadge: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
                .background {
                    Circle().stroke(color.opacity(pulse ? 0 : 0.6), lineWidth: 1.5)
                        .scaleEffect(pulse ? 2.4 : 1)
                }
            Text("生效中")
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Current status

struct OverviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDetails = false
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            hero
            notices
        }
        .padding(.horizontal, 20).padding(.top, 14)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: model.routeState)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: model.changingProxy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.lastError)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.endpointReachable)
    }

    private var hero: some View {
        let state = model.routeState
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                RouteMark(state: state, flowing: !model.changingProxy)
                    .frame(width: 84, height: 84)
                    .padding(12)
                    .background {
                        Circle().fill(RadialGradient(colors: [state.accent.opacity(0.22), .clear],
                                                     center: .center, startRadius: 4, endRadius: 64))
                    }
                VStack(alignment: .leading, spacing: 8) {
                    Text("系统代理")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(palette.secondary)
                    Text(model.changingProxy ? "正在切换…" : state.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                        .id(model.changingProxy ? "switching" : state.title)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    HStack(spacing: 8) {
                        HeroChip(systemImage: model.networkSymbol,
                                 text: model.currentNetwork?.displayName ?? "无主要网络")
                            .help(model.currentNetworkDescription)
                        HeroChip(systemImage: "circle.fill",
                                 text: model.settings.endpoint.display,
                                 tint: endpointTint)
                            .help("代理地址 · \(model.endpointStatusText)")
                    }
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .topTrailing) {
                Button { showDetails.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.mist)
                        .frame(width: 28, height: 28)
                        .background(palette.text.opacity(0.07), in: Circle())
                }
                .buttonStyle(PressFeedbackStyle())
                .help("运行详情")
                .accessibilityLabel("运行详情")
                .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                    diagnostics.environment(\.colorScheme, scheme)
                }
            }

            Rectangle().fill(palette.line).frame(height: 1)

            HStack(spacing: 16) {
                RouteSwitch(state: state, busy: model.changingProxy) { model.setProxyManually($0) }
                    .frame(maxWidth: 240)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Toggle(isOn: Binding(get: { !model.isPaused }, set: { model.setPaused(!$0) })) {
                        Text("自动切换").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.mist)
                    }
                    .toggleStyle(.switch).controlSize(.small).tint(palette.mint)
                    .disabled(model.changingProxy)
                    Text(model.isPaused ? "已暂停 · 保持当前代理" : model.statusText)
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(model.statusText)
                }
            }
        }
        .padding(22)
        .background(HeroBackground(accent: state.accent))
    }

    @ViewBuilder
    private var notices: some View {
        if model.currentNetwork?.kind == .wifi && !model.locationAuthorized {
            LocationAccessHint(service: model.locationService)
                .padding(14)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let error = model.lastError {
            NoticeRow(icon: "exclamationmark.triangle.fill", text: error,
                      actionTitle: "检查设置") { model.showingPreferences = true }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        if model.endpointReachable == false && model.settings.rules.contains(where: { $0.enabled && $0.action == .on }) {
            NoticeRow(icon: "bolt.slash.fill", text: "代理地址不可连接，请检查客户端或修改地址。",
                      actionTitle: "修改地址") { model.showingPreferences = true }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var endpointTint: Color {
        switch model.endpointReachable {
        case true: return palette.mint
        case false: return palette.coral
        case nil: return palette.secondary
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行详情").font(.headline).foregroundStyle(palette.text)
            Label(model.statusText, systemImage: "clock.arrow.circlepath")
            Label(model.systemProxySummary, systemImage: "switch.2")
            Label("\(model.settings.endpoint.display) · \(model.endpointStatusText)", systemImage: "network")
            Text(model.settings.flClash == nil
                 ? "只控制系统代理，TUN 模式不受影响。"
                 : "已配置 Mihomo 联动，手动开关与规则会同步 TUN。")
                .font(.caption)
            HStack {
                Spacer()
                Button("刷新") { model.refreshNetwork(); model.refreshEndpointReachability() }
                Button("立即应用") { model.applyNow() }
                    .buttonStyle(.borderedProminent).tint(palette.mint)
                    .disabled(model.isPaused)
            }
        }
        .font(.callout).foregroundStyle(palette.secondary)
        .padding(18)
        .frame(width: 420)
    }
}

private struct NoticeRow: View {
    let icon: String
    let text: String
    let actionTitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon).foregroundStyle(palette.coral)
            Text(text).font(.callout).foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(palette.coral.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.coral.opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: - Rules

struct RulesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var showingSearch = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmedForInput.isEmpty }

    private var filteredRules: [Rule] {
        let text = query.trimmedForInput
        guard !text.isEmpty else { return model.settings.rules }
        return model.settings.rules.filter { rule in
            if model.networkName(for: rule.network).localizedCaseInsensitiveContains(text) { return true }
            if rule.place?.label.localizedCaseInsensitiveContains(text) == true { return true }
            if case let .wired(interfaceName) = rule.network {
                return interfaceName.localizedCaseInsensitiveContains(text)
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("网络规则").font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                    Text("\(model.enabledRuleCount) 条已启用")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                if !model.settings.rules.isEmpty {
                    if showingSearch {
                        TextField("搜索", text: $query).textFieldStyle(.plain).font(.callout)
                            .padding(.horizontal, 10).frame(width: 160, height: 30)
                            .background(palette.surface, in: Capsule())
                            .overlay { Capsule().stroke(palette.line, lineWidth: 1) }
                            .focused($searchFocused)
                            .task {
                                await Task.yield()
                                searchFocused = true
                            }
                            .onExitCommand {
                                query = ""
                                showingSearch = false
                            }
                    }
                    Button {
                        showingSearch.toggle()
                        if !showingSearch { query = "" }
                    } label: {
                        Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingSearch ? "关闭搜索" : "搜索规则")
                    .help(showingSearch ? "关闭搜索（Esc）" : "搜索规则")
                    Button {
                        model.editingRule = RuleEditorTarget(rule: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(palette.mint)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加规则")
                    .help("添加规则（⌘N）")
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)

            if model.settings.rules.isEmpty {
                EmptyStateView(title: "换个网络，代理自动切换",
                               message: "为常用网络选好代理状态，连上网络时自动匹配。",
                               actionTitle: model.currentNetwork == nil ? "添加第一条规则" : "为当前网络设置规则") {
                    model.editingRule = RuleEditorTarget(rule: nil)
                }
                .transition(.opacity)
            } else {
                List {
                    ForEach(filteredRules) { rule in
                        RuleRow(model: model, rule: rule,
                                priority: (model.settings.rules.firstIndex { $0.id == rule.id } ?? 0) + 1)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                    .onMove(perform: isSearching ? nil : { source, destination in
                        model.moveRules(from: source, to: destination)
                    })
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .help("从上到下匹配 · 拖动排序 · 双击编辑 · 右键更多操作")
                .padding(.horizontal, 8)
                .overlay {
                    if filteredRules.isEmpty {
                        Label("没有匹配的规则", systemImage: "magnifyingglass")
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.settings.rules)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingSearch)
    }
}

// MARK: - Preferences

struct ProxyEndpointSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var endpointHost: String
    @State private var endpointPort: String
    @State private var endpointError: String?
    @State private var editingEndpoint = false

    init(model: AppModel) {
        self.model = model
        _endpointHost = State(initialValue: model.settings.endpoint.host)
        _endpointPort = State(initialValue: String(model.settings.endpoint.port))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "network").foregroundStyle(.tint)
                Text(model.settings.endpoint.display).monospacedDigit()
                    .lineLimit(1).help(model.settings.endpoint.display)
                Spacer()
                if model.endpointReachable == nil {
                    ProgressView().controlSize(.small)
                }
                Text(model.endpointStatusText).foregroundStyle(.secondary)
                Button(editingEndpoint ? "收起" : "修改") {
                    if !editingEndpoint {
                        endpointHost = model.settings.endpoint.host
                        endpointPort = String(model.settings.endpoint.port)
                        endpointError = nil
                    }
                    editingEndpoint.toggle()
                }
                    .buttonStyle(.borderless)
            }
            if editingEndpoint {
                TextField("主机", text: $endpointHost).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("代理主机")
                TextField("端口", text: $endpointPort).monospacedDigit().textFieldStyle(.roundedBorder)
                    .accessibilityLabel("代理端口")
                HStack {
                    if let endpointError {
                        Text(endpointError).font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                    Button("保存地址") { saveEndpoint() }
                }
            }
            if model.endpointReachable == false {
                Label("请检查代理客户端是否运行，或修改地址；关闭代理不受影响。",
                      systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重新检测") { model.refreshEndpointReachability() }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: editingEndpoint)
        .onChange(of: model.settings.endpoint) { endpoint in
            if !editingEndpoint {
                endpointHost = endpoint.host
                endpointPort = String(endpoint.port)
            }
        }
    }

    private func saveEndpoint() {
        guard !endpointHost.trimmedForInput.isEmpty,
              let port = Int(endpointPort), (1...65535).contains(port) else {
            endpointError = "主机不能为空，端口需在 1–65535 之间。"
            return
        }
        if model.setEndpoint(host: endpointHost, portText: endpointPort) {
            endpointError = nil
            editingEndpoint = false
        } else {
            endpointError = model.lastError ?? "保存失败，请重试。"
        }
    }
}

struct PreferencesView: View {
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BrandBadge(size: 40, state: model.routeState)
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置").font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.text)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
            Form {
                Section("外观") {
                    Picker("显示模式", selection: Binding(
                        get: { model.settings.appearance ?? .automatic },
                        set: { model.setAppearance($0) }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("软件更新") {
                    UpdateSettingsView(checker: model.updateChecker)
                }
                Section("代理地址") {
                    ProxyEndpointSettings(model: model)
                }
                Section("Clash / Mihomo 联动") {
                    FlClashSettingsView(model: model)
                }
                Section {
                    Toggle("登录时启动", isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Text(model.loginItemStatus).font(.caption).foregroundStyle(.secondary)
                }
                Section("权限") {
                    LocationPermissionRow(service: model.locationService)
                    HStack {
                        Label("失败通知", systemImage: "bell")
                        Spacer()
                        Text(model.notificationStatus.permissionLabel)
                            .font(.caption).foregroundStyle(.secondary)
                        Button(model.notificationStatus == .notDetermined ? "允许通知" : "系统设置") {
                            model.requestNotificationAccess()
                        }
                        .buttonStyle(.borderless)
                    }
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            HStack {
                if let error = model.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .background(palette.canvas)
        .tint(palette.mint)
        .frame(width: 560, height: 580)
        .task { await model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshPermissions() }
        }
    }


}

// MARK: - Root

struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedNetworkName: String?

    var body: some View {
        VStack(spacing: 0) {
            OverviewView(model: model)
            RulesView(model: model)
        }
        .background(ConsolePalette(scheme: scheme).canvas.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(ConsolePalette(scheme: scheme).mint)
        .frame(minWidth: 520, minHeight: 600)
        .toolbar {
            ToolbarItem {
                Button { model.showingPreferences = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .help("设置（⌘,）")
            }
        }
        .overlay(alignment: .bottom) {
            if let savedNetworkName {
                Label("已保存 · \(savedNetworkName)", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium)).lineLimit(2)
                    .foregroundStyle(Brand.mist)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Brand.tileGradient, in: Capsule())
                    .overlay { Capsule().stroke(Brand.mint.opacity(0.3), lineWidth: 1) }
                    .shadow(color: Brand.ink.opacity(0.3), radius: 12, y: 6)
                    .padding(20)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: savedNetworkName)
        .task(id: savedNetworkName) {
            guard savedNetworkName != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            savedNetworkName = nil
        }
        .sheet(item: $model.editingRule) { target in
            RuleEditorView(existing: target.rule,
                           services: model.availableServices,
                           currentNetwork: model.currentNetwork,
                           knownWiFiNetworks: model.knownWiFiNetworks,
                           locationService: model.locationService,
                           onRefreshWiFi: { model.refreshNetwork() }) { rule in
                let saved = target.rule == nil ? model.addRule(rule) : model.updateRule(rule)
                guard saved else { return model.lastError ?? "保存失败，请重试。" }
                savedNetworkName = model.networkName(for: rule.network)
                return nil
            }
        }
        .sheet(isPresented: $model.showingPreferences) {
            PreferencesView(model: model)
        }
    }
}

// MARK: - Menu bar

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    private var activeRule: Rule? {
        guard let id = model.activeRuleID else { return nil }
        return model.settings.rules.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            autoRow
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, 4)
            footer
        }
        .padding(14)
        .frame(width: 300)
        .background(palette.canvas)
        .foregroundStyle(palette.text)
        .tint(palette.mint)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: model.routeState)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: model.isPaused)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.lastError)
        .onAppear { model.refreshEffectiveProxy() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandBadge(size: 22, state: model.routeState)
            Text("workProxy").font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            iconButton("gearshape", label: "设置") { openMain(preferences: true) }
                .disabled(model.editingRule != nil)
        }
        .padding(.horizontal, 4)
    }

    private var hero: some View {
        let state = model.routeState
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RouteMark(state: state, flowing: !model.changingProxy)
                    .frame(width: 50, height: 50)
                    .padding(6)
                    .background {
                        Circle().fill(RadialGradient(colors: [state.accent.opacity(0.25), .clear],
                                                     center: .center, startRadius: 2, endRadius: 40))
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.changingProxy ? "正在切换…" : state.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                        .id(model.changingProxy ? "switching" : state.title)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    HStack(spacing: 5) {
                        Image(systemName: model.networkSymbol).font(.system(size: 10, weight: .semibold))
                        Text(model.currentNetwork?.displayName ?? "无主要网络")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .help(model.currentNetworkDescription)
                }
                Spacer(minLength: 0)
            }
            RouteSwitch(state: state, busy: model.changingProxy, height: 34) { model.setProxyManually($0) }
        }
        .padding(14)
        .background(HeroBackground(accent: state.accent, cornerRadius: 18))
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: model.changingProxy)
    }

    private var autoRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isPaused ? "hand.raised.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.isPaused ? palette.secondary : palette.mint)
                .frame(width: 30, height: 30)
                .background((model.isPaused ? palette.secondary : palette.mint).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isPaused ? "手动控制" : "自动切换")
                    .font(.system(size: 13, weight: .semibold))
                Text(autoDetail)
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Toggle("自动切换", isOn: Binding(get: { !model.isPaused }, set: { model.setPaused(!$0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(palette.mint)
                .disabled(model.changingProxy)
                .help(model.isPaused ? "恢复自动，立即重新匹配当前网络" : "暂停自动规则，保持当前代理")
        }
        .padding(10)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1) }
    }

    private var autoDetail: String {
        if model.isPaused { return "自动规则已暂停" }
        if let activeRule { return "命中：\(model.networkName(for: activeRule.network))" }
        return model.statusText
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button { openMain() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 12))
                    Text("管理规则")
                    Text("\(model.enabledRuleCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(palette.line, in: Capsule())
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowButtonStyle())
            Spacer()
            Text(model.settings.flClash == nil ? "系统代理" : "系统代理 + TUN")
                .font(.system(size: 10.5)).foregroundStyle(palette.secondary)
            iconButton("power", label: "退出 workProxy") { NSApp.terminate(nil) }
        }
        .foregroundStyle(palette.secondary)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .foregroundStyle(palette.secondary)
        .help(label).accessibilityLabel(label)
    }

    private func openMain(preferences: Bool = false) {
        dismiss()
        model.showingPreferences = preferences
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 菜单栏面板里的轻量按钮：悬停显示底色，按下轻微回弹。
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowButton(configuration: configuration)
    }

    private struct MenuRowButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && isEnabled ? ConsolePalette(scheme: scheme).text : ConsolePalette(scheme: scheme).secondary)
                .background(ConsolePalette(scheme: scheme).text.opacity(hovering && isEnabled ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

// MARK: - Commands

@MainActor
struct WorkProxyCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(checker: model.updateChecker)
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: "settings")
                model.showingPreferences = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("添加规则") {
                openWindow(id: "settings")
                model.editingRule = RuleEditorTarget(rule: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .disabled(model.showingPreferences || model.editingRule != nil)
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
                .preferredColorScheme((model.settings.appearance ?? .automatic).colorScheme)
                .onAppear { model.start() }
        }
        .defaultSize(width: 540, height: 680)
        .windowResizability(.contentMinSize)
        .commands { WorkProxyCommands(model: model) }

        MenuBarExtra {
            MenuBarPanel(model: model)
                .preferredColorScheme((model.settings.appearance ?? .automatic).colorScheme)
                .onAppear { model.start() }
        } label: {
            if model.lastError != nil {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(nsImage: MenuBarGlyph.image(for: model.routeState))
            }
        }
        .menuBarExtraStyle(.window)
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
