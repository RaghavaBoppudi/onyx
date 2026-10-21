import SwiftUI
import UIKit

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3, extraBounce: 0.08)
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(rotation)
            .animation(animation, value: rotation)
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

enum ScreenClass {
    case standard, statusRail, rail

    private static let railAspectThreshold: CGFloat = 1.8

    static func resolve(for size: CGSize) -> ScreenClass {
        let isLandscape = size.width > size.height
        let prefersRail = size.height / max(size.width, 1) < railAspectThreshold

        if UIDevice.current.userInterfaceIdiom == .pad || (prefersRail && isLandscape) {
            return .rail
        }
        return prefersRail ? .statusRail : .standard
    }
}
