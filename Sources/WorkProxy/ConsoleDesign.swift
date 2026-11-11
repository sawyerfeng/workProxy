import SwiftUI
import WorkProxyCore

struct ConsolePalette {
    let scheme: ColorScheme

    var canvas: Color { scheme == .dark ? Color(red: 0.055, green: 0.075, blue: 0.10) : Color(red: 0.97, green: 0.96, blue: 0.93) }
    var surface: Color { scheme == .dark ? Color(red: 0.09, green: 0.12, blue: 0.15) : .white }
    var text: Color { scheme == .dark ? Color(red: 0.92, green: 0.96, blue: 0.95) : Color(red: 0.10, green: 0.18, blue: 0.20) }
    var secondary: Color { scheme == .dark ? Color(red: 0.62, green: 0.71, blue: 0.74) : Color(red: 0.35, green: 0.43, blue: 0.44) }
    var mint: Color { scheme == .dark ? Color(red: 0.40, green: 0.89, blue: 0.75) : Color(red: 0.03, green: 0.40, blue: 0.34) }
    var coral: Color { scheme == .dark ? Color(red: 1, green: 0.60, blue: 0.42) : Color(red: 0.72, green: 0.27, blue: 0.16) }
    var line: Color { text.opacity(scheme == .dark ? 0.12 : 0.09) }

    func actionColor(_ action: ProxyAction) -> Color { action == .on ? mint : coral }
}

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

/// A state illustration, not a traffic chart or a claim about the active route.
struct NetworkSculpture: View {
    let networkIcon: String
    let proxyIcon: String
    let tint: Color
    let paused: Bool
    let identity: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var drawn = false

    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 188, height: 188)
                .blur(radius: 20)
                .offset(x: 14, y: 0)
            Circle()
                .stroke(tint.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                .frame(width: 192, height: 192)
                .rotationEffect(.degrees(appeared ? 14 : -30))
            Circle()
                .trim(from: 0.02, to: drawn ? 0.78 : 0.02)
                .stroke(tint.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 152, height: 152)
                .rotationEffect(.degrees(-110))

            Path { path in
                path.move(to: CGPoint(x: 42, y: 155))
                path.addCurve(to: CGPoint(x: 130, y: 100),
                              control1: CGPoint(x: 86, y: 155), control2: CGPoint(x: 72, y: 100))
                path.addCurve(to: CGPoint(x: 232, y: 46),
                              control1: CGPoint(x: 194, y: 100), control2: CGPoint(x: 174, y: 46))
            }
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(tint.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))

            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 108, height: 108)
                .overlay {
                    RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.35), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: proxyIcon)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(scheme == .dark ? palette.canvas : .white)
                        .id(proxyIcon).transition(.opacity)
                }
                .shadow(color: tint.opacity(0.3), radius: 20, x: 0, y: 14)
                .rotationEffect(.degrees(appeared ? -9 : -24))
                .scaleEffect(appeared ? 1 : 0.65)
                .offset(y: appeared ? 0 : 24)

            satellite(networkIcon, color: palette.mint)
                .offset(x: -88, y: 55)
                .scaleEffect(appeared ? 1 : 0.4)
            satellite(paused ? "pause.fill" : "bolt.fill", color: palette.coral)
                .offset(x: 102, y: -54)
                .scaleEffect(appeared ? 1 : 0.4)
            Circle().fill(palette.coral).frame(width: 9, height: 9).offset(x: 67, y: 75)
            Circle().fill(palette.mint.opacity(0.6)).frame(width: 5, height: 5).offset(x: -52, y: -81)
        }
        .frame(width: 260, height: 200)
        .opacity(appeared ? 1 : 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: identity + String(reduceMotion)) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appeared = reduceMotion
                drawn = reduceMotion
            }
            guard !reduceMotion else { return }
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.9).delay(0.12)) { drawn = true }
        }
    }

    private func satellite(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 52, height: 52)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(color.opacity(0.25), lineWidth: 1) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.08), radius: 10, y: 6)
    }
}

struct ProxyActionChoices: View {
    @Binding var selection: ProxyAction
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight
    private var palette: ConsolePalette { ConsolePalette(scheme: scheme) }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProxyAction.allCases, id: \.self) { action in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.75)) {
                        selection = action
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: action == .on ? "network" : "network.slash")
                                .font(.system(size: 23, weight: .medium))
                            Spacer()
                            Image(systemName: selection == action ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                        }
                        Text(action.displayName).font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(selection == action ? palette.actionColor(action) : palette.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if selection == action {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(palette.actionColor(action).opacity(0.12))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selection == action ? palette.actionColor(action).opacity(0.6) : palette.line,
                                    lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityLabel(action.displayName)
                .accessibilityAddTraits(selection == action ? .isSelected : [])
            }
        }
    }
}
