import SwiftUI

extension EnvironmentValues {
    @Entry var glyphRotation: Angle = .zero
}

extension View {
    func rotatesWithDevice() -> some View {
        modifier(GlyphRotationModifier())
    }
}

private struct GlyphRotationModifier: ViewModifier {
    @Environment(\.glyphRotation) private var rotation

    func body(content: Content) -> some View {
        content
            .rotationEffect(rotation)
            .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: rotation)
    }
}
