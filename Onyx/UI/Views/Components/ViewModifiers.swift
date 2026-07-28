import SwiftUI

struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let isBordered: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: shape)
                .overlay(
                    shape.strokeBorder(isBordered ? Theme.Color.glassBorderStrong : .clear, lineWidth: Theme.Layout.borderWidth)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(isBordered ? Theme.Color.glassBorderSubtle : .clear, lineWidth: Theme.Layout.borderWidth)
                )
        }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(shape: S, isBordered: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(shape: shape, isBordered: isBordered))
    }
    
    func liquidGlass(isBordered: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(shape: Capsule(), isBordered: isBordered))
    }
}
