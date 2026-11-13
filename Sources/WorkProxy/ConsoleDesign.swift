import AppKit
import SwiftUI
import WorkProxyCore

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .automatic: return "自动切换"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - Palette

/// 取自应用图标：深青底色、薄荷色“出站”箭头（代理）、雾白色“回程”箭头（直连）。
/// 珊瑚色只用于警告与失败，不再代表“关闭”。
struct ConsolePalette {
    let scheme: ColorScheme

    var canvas: Color { scheme == .dark ? Color(red: 0.047, green: 0.078, blue: 0.09) : Color(red: 0.95, green: 0.965, blue: 0.96) }
    var surface: Color { scheme == .dark ? Color(red: 0.078, green: 0.125, blue: 0.145) : .white }
    var text: Color { scheme == .dark ? Color(red: 0.925, green: 0.953, blue: 0.93) : Color(red: 0.07, green: 0.15, blue: 0.17) }
    var secondary: Color { scheme == .dark ? Color(red: 0.63, green: 0.71, blue: 0.70) : Color(red: 0.32, green: 0.41, blue: 0.42) }
    var mint: Color { scheme == .dark ? Color(red: 0.48, green: 0.92, blue: 0.76) : Color(red: 0.02, green: 0.42, blue: 0.34) }
    var mist: Color { scheme == .dark ? Color(red: 0.80, green: 0.90, blue: 0.87) : Color(red: 0.24, green: 0.33, blue: 0.36) }
    var coral: Color { scheme == .dark ? Color(red: 0.95, green: 0.62, blue: 0.48) : Color(red: 0.70, green: 0.27, blue: 0.15) }
    var line: Color { text.opacity(scheme == .dark ? 0.10 : 0.08) }

    func actionColor(_ action: ProxyAction) -> Color { action == .on ? mint : mist }
}

/// 图标原色，用于始终为深色的品牌面板。
enum Brand {
    static let mint = Color(red: 0.48, green: 0.94, blue: 0.77)
    static let mist = Color(red: 0.84, green: 0.94, blue: 0.91)
    static let coral = Color(red: 0.95, green: 0.62, blue: 0.48)
    static let ink = Color(red: 0.035, green: 0.075, blue: 0.10)
    static let deep = Color(red: 0.12, green: 0.23, blue: 0.25)
    static let muted = Color(red: 0.62, green: 0.74, blue: 0.72)

    static var tileGradient: LinearGradient {
        LinearGradient(colors: [deep, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Route state

enum RouteState: Equatable {
    case proxy
    case direct
    case partial
    case unknown

    init(_ state: SystemProxyState) {
        switch state {
        case .on: self = .proxy
        case .off: self = .direct
        case .mixed: self = .partial
        case .unknown: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .proxy: return "代理已开启"
        case .direct: return "代理已关闭"
        case .partial: return "部分开启"
        case .unknown: return "正在读取"
        }
    }

    var accent: Color {
        switch self {
        case .proxy: return Brand.mint
        case .direct: return Brand.mist
        case .partial: return Brand.coral
        case .unknown: return Brand.muted
        }
    }
}

extension AppModel {
    var routeState: RouteState { RouteState(systemProxyState) }

    /// 最近一次自动决策命中的规则。
    var activeRuleID: UUID? {
        if case let .action(_, ruleID) = lastDecision { return ruleID }
        return nil
    }

    var networkSymbol: String {
        switch currentNetwork?.kind {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        case .other: return "network"
        case nil: return "wifi.slash"
        }
    }
}

// MARK: - Logo geometry

/// 图标中的两条相向箭头。坐标取自 scripts/make-app-icon.swift，
/// 映射到去掉圆角底板后的方形区域；整体关于中心点对称。
struct RouteArrow: Shape {
    enum Direction { case outbound, inbound }

    var direction: Direction
    var includesHead = true

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * (x - 0.16) / 0.68,
                    y: rect.minY + rect.height * (0.84 - y) / 0.68)
        }
        var path = Path()
        switch direction {
        case .outbound:
            path.move(to: p(0.28, 0.53))
            path.addCurve(to: p(0.43, 0.67), control1: p(0.28, 0.62), control2: p(0.34, 0.67))
            path.addLine(to: p(0.72, 0.67))
            if includesHead {
                path.move(to: p(0.62, 0.77))
                path.addLine(to: p(0.72, 0.67))
                path.addLine(to: p(0.62, 0.57))
            }
        case .inbound:
            path.move(to: p(0.72, 0.47))
            path.addCurve(to: p(0.57, 0.33), control1: p(0.72, 0.38), control2: p(0.66, 0.33))
            path.addLine(to: p(0.28, 0.33))
            if includesHead {
                path.move(to: p(0.38, 0.43))
                path.addLine(to: p(0.28, 0.33))
                path.addLine(to: p(0.38, 0.23))
            }
        }
        return path
    }

    static func lineWidth(for side: CGFloat) -> CGFloat { side * 0.0985 }
}

/// 状态化的品牌标志：当前路线的箭头点亮并重新描绘，另一条退为暗线。
/// `flowing` 时沿点亮的路线流动数据包。
struct RouteMark: View {
    let state: RouteState
    var flowing = false
    var dimmed: Double = 0.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drawn: CGFloat = 1
    @State private var spin: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let width = RouteArrow.lineWidth(for: side)
            ZStack {
                arrow(.outbound, color: ConsolePalette(scheme: scheme).mint, lit: state == .proxy || state == .partial, width: width)
                arrow(.inbound, color: ConsolePalette(scheme: scheme).mist, lit: state == .direct || state == .partial, width: width)
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(spin))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: state)
        .onChange(of: state) { _ in
            guard !reduceMotion else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drawn = 0 }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) { spin += 360 }
            withAnimation(.easeOut(duration: 0.65).delay(0.15)) { drawn = 1 }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func arrow(_ direction: RouteArrow.Direction, color: Color, lit: Bool, width: CGFloat) -> some View {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        ZStack {
            RouteArrow(direction: direction).stroke(color.opacity(dimmed), style: style)
            if lit {
                RouteArrow(direction: direction)
                    .trim(from: 0, to: drawn)
                    .stroke(color, style: style)
                    .shadow(color: color.opacity(0.55), radius: width * 0.9)
                    .transition(.opacity)
                if flowing && !reduceMotion && state != .partial {
                    PacketFlow(direction: direction, width: width)
                }
            }
        }
    }
}

/// 沿路线移动的小点；只是状态示意，不代表真实流量。
private struct PacketFlow: View {
    let direction: RouteArrow.Direction
    let width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let gap = width * 3.2
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = -CGFloat(t.truncatingRemainder(dividingBy: 1.4) / 1.4) * gap
            RouteArrow(direction: direction, includesHead: false)
                .stroke(Brand.ink.opacity(0.55),
                        style: StrokeStyle(lineWidth: width * 0.34, lineCap: .round,
                                           dash: [0.1, gap], dashPhase: phase))
        }
    }
}

/// 小尺寸的品牌徽标，带图标的深色圆角底板。
struct BrandBadge: View {
    var size: CGFloat = 28
    var state: RouteState = .partial

    var body: some View {
        RouteMark(state: state, dimmed: 0.25)
            .environment(\.colorScheme, .dark)
            .padding(size * 0.16)
            .frame(width: size, height: size)
            .background(Brand.tileGradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .stroke(Brand.mist.opacity(0.18), lineWidth: 0.5)
            }
    }
}

/// 深色品牌面板：图标同款渐变 + 当前路线颜色的柔光。
struct HeroBackground: View {
    let accent: Color
    var cornerRadius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(scheme == .dark ? Brand.tileGradient : LinearGradient(
                colors: [Color(red: 0.84, green: 0.94, blue: 0.90), .white],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.28), .clear],
                                         center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 280, height: 280)
                    .offset(x: -90, y: -110)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [ConsolePalette(scheme: scheme).mist.opacity(0.22), ConsolePalette(scheme: scheme).mist.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: Brand.ink.opacity(scheme == .dark ? 0.25 : 0.06), radius: 18, y: 10)
    }
}

// MARK: - Controls

struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

/// 深色面板上的“代理 / 直连”分段开关，滑块随状态移动。
struct RouteSwitch: View {
    let state: RouteState
    let busy: Bool
    var height: CGFloat = 38
    let onSelect: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }
    @Namespace private var thumb
    @State private var hovered: Bool? = nil

    var body: some View {
        HStack(spacing: 4) {
            segment(enabled: true, title: "代理", direction: .outbound, color: palette.mint)
            segment(enabled: false, title: "直连", direction: .inbound, color: palette.mist)
        }
        .padding(4)
        .background(palette.text.opacity(0.07), in: RoundedRectangle(cornerRadius: height * 0.36 + 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: height * 0.36 + 4, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }

    private func segment(enabled: Bool, title: String, direction: RouteArrow.Direction, color: Color) -> some View {
        let active = enabled ? state == .proxy : state == .direct
        return Button {
            guard !active else { return }
            onSelect(enabled)
        } label: {
            HStack(spacing: 7) {
                if busy && !active {
                    ProgressView().controlSize(.mini).tint(Brand.mist)
                } else {
                    RouteArrow(direction: direction)
                        .stroke(active ? (scheme == .dark ? Brand.ink : .white) : color.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                }
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(active ? (scheme == .dark ? Brand.ink : .white) : palette.mist.opacity(hovered == enabled ? 1 : 0.75))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                        .fill(color)
                        .shadow(color: color.opacity(0.35), radius: 8, y: 2)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                } else if hovered == enabled {
                    RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: height * 0.36, style: .continuous))
        }
        .buttonStyle(PressFeedbackStyle())
        .disabled(busy)
        .onHover { hovered = $0 ? enabled : (hovered == enabled ? nil : hovered) }
        .accessibilityLabel(enabled ? "开启代理" : "关闭代理")
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(enabled ? "立即开启代理，并暂停自动规则" : "立即关闭代理，并暂停自动规则")
    }
}

/// 深色面板上的信息胶囊。
struct HeroChip: View {
    let systemImage: String
    let text: String
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint ?? palette.secondary)
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(palette.mist)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(palette.text.opacity(0.07), in: Capsule())
        .overlay { Capsule().stroke(palette.line, lineWidth: 1) }
    }
}

/// 规则编辑器中的动作选择，两张卡片对应图标的两条箭头。
struct ProxyActionChoices: View {
    @Binding var selection: ProxyAction
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProxyAction.allCases, id: \.self) { action in
                let selected = selection == action
                let color = palette.actionColor(action)
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.75)) {
                        selection = action
                    }
                } label: {
                    HStack(spacing: 12) {
                        RouteArrow(direction: action == .on ? .outbound : .inbound)
                            .stroke(selected ? color : palette.secondary.opacity(0.6),
                                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.displayName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(selected ? palette.text : palette.secondary)
                            Text(action == .on ? "使用已配置的代理地址" : "停止使用系统代理地址")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? color : palette.secondary.opacity(0.5))
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(color.opacity(0.10))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? color.opacity(0.55) : palette.line, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityLabel(action.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Menu bar glyph

/// 菜单栏模板图标：图标的两条箭头，当前路线实心，另一条半透明。
@MainActor
enum MenuBarGlyph {
    static func image(for state: RouteState) -> NSImage {
        let points: CGFloat = 18
        let scale: CGFloat = 2
        let pixels = Int(points * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil) ?? NSImage()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        let side = CGFloat(pixels)
        // RouteArrow 使用 y 向下坐标；位图上下翻转后复用同一几何。
        cg.translateBy(x: 0, y: side)
        cg.scaleBy(x: 1, y: -1)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let width = RouteArrow.lineWidth(for: side) * 1.12

        let outboundAlpha: CGFloat = state == .direct ? 0.38 : 1
        let inboundAlpha: CGFloat = state == .proxy ? 0.38 : 1
        let strokes: [(RouteArrow.Direction, CGFloat)] = [(.outbound, outboundAlpha), (.inbound, inboundAlpha)]
        for (direction, alpha) in strokes {
            cg.addPath(RouteArrow(direction: direction).path(in: rect).cgPath)
            cg.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            cg.setLineWidth(width)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        image.isTemplate = true
        image.accessibilityDescription = "workProxy"
        return image
    }
}
