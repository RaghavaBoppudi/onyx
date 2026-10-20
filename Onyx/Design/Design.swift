import SwiftUI

nonisolated extension Color {
    static var onyxAccent: Color {
        Color(red: 111.0 / 255, green: 135.0 / 255, blue: 152.0 / 255)
    }
}

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

nonisolated enum Metrics {

    enum Viewfinder {
        static let cornerRadius: CGFloat = 22
        static let inset: CGFloat = 14
        static let portraitAspect: CGFloat = 3.0 / 4.0
        static let landscapeAspect: CGFloat = 4.0 / 3.0

        static func aspect(isLandscape: Bool) -> CGFloat {
            isLandscape ? landscapeAspect : portraitAspect
        }
    }

    enum Dual {
        static let insetScale: CGFloat = 0.30
        static let insetMarginFraction: CGFloat = 0.04
        static let insetCornerFraction: CGFloat = 0.14
        static let splitMinimumShortSide: CGFloat = 560
    }

    enum Blink {
        static let opacity: Double = 0.42
        static let inDuration: Double = 0.055
        static let outDuration: Double = 0.13
    }
}
