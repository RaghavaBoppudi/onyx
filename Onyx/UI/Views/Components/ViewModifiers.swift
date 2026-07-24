import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let isBordered: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isBordered ? 0.4 : 0.0), lineWidth: 0.5)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isBordered ? 0.2 : 0.0), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func liquidGlass(isBordered: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(isBordered: isBordered))
    }
}
