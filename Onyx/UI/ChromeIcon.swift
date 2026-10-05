import SwiftUI

enum ChromeRole {
    case toggle
    case action
}

struct ChromeIcon: View {
    @Environment(\.theme) private var theme
    @Environment(\.glyphRotation) private var rotation
    @ScaledMetric(relativeTo: .title3) private var symbolSize: CGFloat = 21

    let symbol: SymbolPair
    var role: ChromeRole = .toggle
    var isActive: Bool = false
    var badge: Bool = false
    var weight: Font.Weight = .regular
    var rotatesWithDevice: Bool = true
    let action: () -> Void

    private var tint: Color {
        switch role {
        case .toggle: isActive ? theme.iconActive : theme.secondary
        case .action: theme.iconActive
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? symbol.filled : symbol.outline)
                .font(.system(size: min(symbolSize, 27), weight: weight))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -2)
                    }
                }
                .rotationEffect(rotatesWithDevice ? rotation : .zero)
                .onyxAnimation(Metrics.Motion.glyphRotation, value: rotation)
                .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(ChromePressStyle())
    }
}

struct ChromePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

struct PillButton: View {
    @Environment(\.theme) private var theme

    let title: String
    var systemImage: String? = nil
    var badge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                if badge {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .font(Typography.pill)
            .foregroundStyle(theme.iconActive)
            .padding(.horizontal, 14)
            .frame(minWidth: Metrics.Chrome.modePillWidth, minHeight: Metrics.Chrome.modePillHeight)
            .onyxPill()
            .padding(.vertical, (Metrics.Chrome.modeButtonHeight - Metrics.Chrome.modePillHeight) / 2)
            .contentShape(.rect)
        }
        .buttonStyle(ChromePressStyle())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
