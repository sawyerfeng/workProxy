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
                .foregroundStyle(.tint)
                .frame(width: 80, height: 80)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
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

struct LocationAccessHint: View {
    @ObservedObject var service: LocationService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.slash").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("需要定位权限").font(.callout.weight(.medium))
                Text("macOS 需要定位权限来读取 Wi-Fi 名称，即使不设置地点条件。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                Image(systemName: existing == nil ? "plus.circle.fill" : "slider.horizontal.3")
                    .font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text("选好网络，剩下的交给自动切换。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)

            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: draft.networkKind == .wifi ? "wifi" : "cable.connector")
                            .font(.title3).foregroundStyle(.tint)
                        Text(selectedNetworkName).fontWeight(.medium)
                            .lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button(showNetworkOptions ? "收起" : "更换") {
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
                    if draft.networkKind == .wifi && draft.ssid.trimmedForInput.isEmpty {
                        Text("未读取到当前 Wi-Fi 名称，请选择网络或手动输入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("连接这个网络时")
                }

                Section {
                    ProxyActionChoices(selection: $draft.action)
                    if let rule = draft.makeRule(id: existing?.id ?? UUID()) {
                        Label("连接 \(selectedNetworkName) 时，\(rule.action.displayName)",
                              systemImage: "arrow.turn.down.right")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if draft.usePlace && draft.hasPlaceCoordinates {
                        Label("仅在 \(draft.placeLabel.isEmpty ? "指定地点" : draft.placeLabel) 附近 \(Int(draft.radius)) 米内",
                              systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle(isOn: $draft.usePlace) {
                        Label("只在指定地点生效", systemImage: "map.fill")
                            .font(.headline)
                            .foregroundStyle(palette.mint)
                    }
                    if draft.usePlace {
                        if draft.networkKind != .wifi && !locationService.isAuthorized {
                            LocationAccessHint(service: locationService)
                        }
                        placeEditor
                    } else {
                        Text("可添加家庭或公司地址，避免同名网络误匹配。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("地点条件")
                }

                Section {
                    TextField("规则名称（可选）", text: $draft.name, prompt: Text("自动命名"))
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red)
                } else {
                    Text("保存规则后，在下次网络事件时自动匹配。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.mint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(20)
        }
        .background(palette.canvas)
        .tint(palette.mint)
        .frame(width: 600, height: 740)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    private var accent: Color { palette.actionColor(rule.action) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: networkIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(rule.enabled ? accent : palette.secondary)
                .frame(width: 48, height: 48)
                .background(accent.opacity(rule.enabled ? 0.12 : 0.04),
                            in: RoundedRectangle(cornerRadius: 16))
                .rotationEffect(.degrees(hovering && !reduceMotion ? -6 : 0))
                .scaleEffect(rule.enabled ? 1 : 0.86)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(networkDescription).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.text).lineLimit(1)
                    .help(networkDescription)
                if let place = rule.place {
                    Label("\(place.label) · \(Int(place.radiusMeters)) 米", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1)
                } else {
                    Text(rule.name).font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1)
                }
            }
            .opacity(rule.enabled ? 1 : 0.55)
            Spacer(minLength: 8)
            Label(rule.action == .on ? "开启代理" : "关闭代理",
                  systemImage: rule.action == .on ? "arrow.up.right" : "minus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(accent.opacity(0.10), in: Capsule())
                .fixedSize()
            Button {
                model.editingRule = RuleEditorTarget(rule: rule)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("编辑规则")
            .accessibilityLabel("编辑规则 \(rule.name)")
            Toggle("启用规则 \(rule.name)", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(rule.id, $0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(accent)
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(hovering ? accent.opacity(0.35) : palette.line, lineWidth: 1)
        }
        .shadow(color: accent.opacity(hovering ? 0.10 : 0), radius: 10, y: 4)
        .offset(y: hovering && !reduceMotion ? -2 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.7), value: hovering)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.7), value: rule.enabled)
        .contextMenu {
            Button("编辑") { model.editingRule = RuleEditorTarget(rule: rule) }
            Button("复制") {
                model.addRule(Rule(name: "\(rule.name) 副本", network: rule.network,
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

    private var networkIcon: String {
        switch rule.network {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        }
    }

    private var networkDescription: String {
        switch rule.network {
        case let .wifi(ssid): return ssid
        case let .wired(interfaceName):
            return model.availableServices.first { $0.device == interfaceName }?.name ?? interfaceName
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                NetworkSculpture(networkIcon: networkIcon, proxyIcon: proxyIcon,
                                 tint: proxyTint, paused: model.isPaused,
                                 identity: model.systemProxySummary + model.currentNetworkDescription + String(model.isPaused))
                    .scaleEffect(0.46)
                    .frame(width: 120, height: 92)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("系统代理").font(.callout).foregroundStyle(palette.secondary)
                        Text(proxyTitle)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.text)
                            .id(proxyTitle).transition(.opacity)
                        Spacer()
                        Button { showDetails.toggle() } label: {
                            Image(systemName: "info.circle")
                                .font(.body).foregroundStyle(palette.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("运行详情")
                        .accessibilityLabel("运行详情")
                        .popover(isPresented: $showDetails, arrowEdge: .bottom) { diagnostics }
                    }
                    Label(model.currentNetworkDescription, systemImage: networkIcon)
                        .font(.callout.weight(.medium)).foregroundStyle(palette.secondary)
                        .lineLimit(2).textSelection(.enabled)
                    HStack(spacing: 10) {
                        Toggle("自动切换", isOn: Binding(
                            get: { !model.isPaused }, set: { model.setPaused(!$0) }
                        ))
                        .toggleStyle(.switch).controlSize(.small).tint(palette.mint).fixedSize()
                        Text(model.isPaused ? "已暂停，保持当前代理" : "网络变化时自动匹配")
                            .font(.caption).foregroundStyle(palette.secondary)
                    }
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [palette.mint.opacity(scheme == .dark ? 0.13 : 0.08),
                                                  palette.surface, palette.coral.opacity(0.09)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1) }

            if model.currentNetwork?.kind == .wifi && !model.locationAuthorized {
                LocationAccessHint(service: model.locationService)
                    .padding(14).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            if let error = model.lastError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.coral)
                    Text(error).font(.callout)
                    Spacer()
                    Button("检查设置") { model.showingPreferences = true }
                }
                .padding(14).background(palette.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
            if model.endpointReachable == false && model.settings.rules.contains(where: { $0.enabled && $0.action == .on }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.slash").foregroundStyle(palette.coral)
                    Text("代理地址不可连接，请检查客户端或修改地址。")
                        .font(.callout).foregroundStyle(palette.secondary)
                    Spacer()
                    Button("修改地址") { model.showingPreferences = true }
                }
                .padding(14).background(palette.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: showDetails)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.systemProxySummary)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.statusText, systemImage: "clock.arrow.circlepath")
            HStack {
                Label("\(model.settings.endpoint.display) · \(model.endpointStatusText)",
                      systemImage: "network")
                Spacer()
                Button("立即应用") { model.applyNow() }.disabled(model.isPaused)
                Button("刷新") { model.refreshNetwork(); model.refreshEndpointReachability() }
            }
            Text("只控制系统代理，TUN 模式不受影响。")
                .font(.caption)
        }
        .font(.callout).foregroundStyle(palette.secondary)
        .padding(16).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 460)
    }

    private var networkIcon: String {
        switch model.currentNetwork?.kind {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        case .other: return "network"
        case nil: return "network.slash"
        }
    }

    private var proxyTitle: String {
        switch model.systemProxyState {
        case .on: return "已开启"
        case .off: return "已关闭"
        case .mixed: return "部分开启"
        case .unknown: return "等待读取"
        }
    }

    private var proxyTint: Color {
        switch model.systemProxyState {
        case .on: return palette.mint
        case .off: return palette.coral
        case .mixed: return palette.coral
        case .unknown: return palette.secondary
        }
    }

    private var proxyIcon: String {
        switch model.systemProxyState {
        case .on: return "network"
        case .off: return "network.slash"
        case .mixed: return "exclamationmark.triangle"
        case .unknown: return "questionmark"
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

    private var isSearching: Bool { !query.trimmedForInput.isEmpty }

    private var filteredRules: [Rule] {
        let text = query.trimmedForInput
        guard !text.isEmpty else { return model.settings.rules }
        return model.settings.rules.filter { rule in
            if rule.name.localizedCaseInsensitiveContains(text) { return true }
            switch rule.network {
            case let .wifi(ssid): return ssid.localizedCaseInsensitiveContains(text)
            case let .wired(interfaceName):
                let service = model.availableServices.first { $0.device == interfaceName }?.name ?? interfaceName
                return service.localizedCaseInsensitiveContains(text)
                    || interfaceName.localizedCaseInsensitiveContains(text)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的网络").font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                    Text("\(model.enabledRuleCount) 条规则已启用")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                if !model.settings.rules.isEmpty {
                    TextField("搜索规则", text: $query)
                        .textFieldStyle(.roundedBorder).frame(width: 140)
                    Button {
                        model.editingRule = RuleEditorTarget(rule: nil)
                    } label: {
                        Label("添加规则", systemImage: "plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.surface)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(palette.mint, in: Capsule())
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .help("添加规则（⌘N）")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            if model.settings.rules.isEmpty {
                EmptyStateView(systemImage: "point.3.connected.trianglepath.dotted",
                               title: "换个网络，自动切换",
                               message: "为常用网络选好代理状态，连接时就会自动匹配。",
                               actionTitle: model.currentNetwork == nil ? "添加第一条规则" : "为当前网络设置规则") {
                    model.editingRule = RuleEditorTarget(rule: nil)
                }
            } else {
                List {
                    ForEach(filteredRules) { rule in
                        RuleRow(model: model, rule: rule)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    }
                    .onMove(perform: isSearching ? nil : { source, destination in
                        model.moveRules(from: source, to: destination)
                    })
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .overlay {
                    if filteredRules.isEmpty {
                        Label("没有匹配的规则", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("从上到下匹配 · 拖动调整优先级").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.settings.rules)
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
            HStack(spacing: 12) {
                Image(systemName: "gearshape").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置").font(.title2.weight(.semibold))
                    Text("配置一次，所有网络规则共用。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            Form {
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
                        VStack(alignment: .leading, spacing: 4) {
                            Label("失败通知", systemImage: "bell")
                            Text("规则执行失败时提醒，可选")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
    @State private var savedRuleName: String?

    var body: some View {
        VStack(spacing: 0) {
            OverviewView(model: model)
            RulesView(model: model)
        }
        .background(ConsolePalette(scheme: scheme).canvas)
        .tint(ConsolePalette(scheme: scheme).mint)
        .frame(minWidth: 640, minHeight: 540)
        .toolbar {
            ToolbarItem {
                Button { model.showingPreferences = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .help("设置（⌘,）")
            }
        }
        .overlay(alignment: .bottom) {
            if let savedRuleName {
                Label("已保存 · \(savedRuleName)", systemImage: "checkmark.circle.fill")
                    .font(.callout).lineLimit(2)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(20)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7), value: savedRuleName)
        .task(id: savedRuleName) {
            guard savedRuleName != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            savedRuleName = nil
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
                savedRuleName = rule.name
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
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    private var proxyOn: Bool { model.systemProxyState == .on }

    private var stateTitle: String {
        if model.changingProxy { return "正在切换" }
        switch model.systemProxyState {
        case .on: return "已开启"
        case .off: return "已关闭"
        case .mixed: return "部分开启"
        case .unknown: return "状态未知"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("workProxy")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button { openMain(preferences: true) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(palette.surface, in: Circle())
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityLabel("设置")
                .disabled(model.editingRule != nil)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: proxyOn ? "network" : "network.slash")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(proxyOn ? palette.mint : palette.secondary)
                        .frame(width: 52, height: 52)
                        .background(palette.mint.opacity(proxyOn ? 0.12 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统代理").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondary)
                        Text(stateTitle).font(.system(size: 25, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    if model.changingProxy {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle().fill(proxyOn ? palette.mint : palette.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text(model.currentNetworkDescription).lineLimit(1)
                }
                .font(.system(size: 12)).foregroundStyle(palette.secondary)

                HStack(spacing: 4) {
                    proxyButton("开启", icon: "power", enabled: true)
                    proxyButton("关闭", icon: "power", enabled: false)
                }
                .padding(4)
                .background(palette.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
                .disabled(model.changingProxy)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [palette.mint.opacity(0.08), palette.surface],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1) }

            HStack(spacing: 10) {
                Image(systemName: model.isPaused ? "hand.raised" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 14)).foregroundStyle(palette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isPaused ? "手动控制" : "自动切换")
                        .font(.system(size: 13, weight: .medium))
                    Text(model.isPaused ? "自动规则已暂停" : "跟随网络规则")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Button(model.isPaused ? "恢复自动" : "暂停") {
                    model.setPaused(!model.isPaused)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.mint)
                .buttonStyle(.plain)
                .disabled(model.changingProxy)
            }
            .padding(.horizontal, 2)

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button { openMain() } label: {
                    HStack(spacing: 5) {
                        Text("管理规则")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                Spacer()
                Text(model.settings.flClash == nil ? "系统代理" : "系统代理 + TUN")
                    .font(.system(size: 10))
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: 24, height: 24)
                }
                .help("退出 workProxy").accessibilityLabel("退出 workProxy")
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 320)
        .background(palette.canvas)
        .foregroundStyle(palette.text)
        .tint(palette.mint)
        .onAppear { model.refreshEffectiveProxy() }
    }

    private func proxyButton(_ title: String, icon: String, enabled: Bool) -> some View {
        let active = enabled ? proxyOn : model.systemProxyState == .off
        return Button { model.setProxyManually(enabled) } label: {
            HStack(spacing: 6) {
                Image(systemName: active ? "checkmark" : icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? palette.canvas : palette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(active ? palette.mint : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityLabel(title + "代理")
        .help("立即" + title + "代理，并暂停自动规则")
    }

    private func openMain(preferences: Bool = false) {
        dismiss()
        model.showingPreferences = preferences
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
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
                .onAppear { model.start() }
        }
        .defaultSize(width: 680, height: 600)
        .windowResizability(.contentMinSize)
        .commands { WorkProxyCommands(model: model) }

        MenuBarExtra("workProxy", systemImage: model.menuBarIcon) {
            MenuBarPanel(model: model)
                .onAppear { model.start() }
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
