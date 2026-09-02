import SwiftUI

struct ChromeIcon: View {
    @Environment(\.theme) private var theme

    let symbol: SymbolPair
    var isActive: Bool = false
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? symbol.filled : symbol.outline)
                .font(Metrics.Chrome.symbolFont)
                .foregroundStyle(theme.icon(active: isActive))
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(rotation)
                .animation(Metrics.Motion.glyphRotation, value: rotation)
                .frame(width: Metrics.Chrome.tapTarget,
                       height: Metrics.Chrome.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
