import SwiftUI
import UIKit

nonisolated enum Typography {
    static func lens(active: Bool) -> Font {
        .body.weight(active ? .semibold : .regular)
    }

    static let pill        = Font.subheadline.weight(.semibold)
    static let caption     = Font.caption
    static let body        = Font.body
    static let lookTitle   = Font.title2.weight(.semibold)
}

nonisolated struct SymbolPair {
    let outline: String
    let filled: String
}

nonisolated enum Symbols {
    static let grid = SymbolPair(outline: "square.grid.3x3", filled: "square.grid.3x3.fill")

    static let flashOff = SymbolPair(outline: "bolt.slash", filled: "bolt.slash.fill")
    static let flashOn  = SymbolPair(outline: "bolt", filled: "bolt.fill")

    static let modes = SymbolPair(outline: "camera.filters", filled: "camera.filters")
    static let cancel = SymbolPair(outline: "xmark.circle", filled: "xmark.circle.fill")
    static let cameraFlip = SymbolPair(
        outline: "arrow.triangle.2.circlepath.camera",
        filled: "arrow.triangle.2.circlepath.camera.fill"
    )

    static let back = SymbolPair(outline: "chevron.left", filled: "chevron.left")
    static let dual = SymbolPair(outline: "pip", filled: "pip.fill")
    static let geotag = SymbolPair(outline: "location", filled: "location.fill")
    static let noPermission = "camera.metering.unknown"
}

extension EnvironmentValues {
    @Entry var glyphRotation: Angle = .zero
    @Entry var isBrowsingModes: Bool = false
}

nonisolated enum ViewfinderSpace {
    static let name = "viewfinder"
}

nonisolated struct ModesIconFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

extension View {
    func onyxPill() -> some View {
        modifier(OnyxPill())
    }

    func restricted(_ isRestricted: Bool) -> some View {
        disabled(isRestricted).opacity(isRestricted ? 0.35 : 1)
    }
}

private struct OnyxPill: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.pillFill, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
            }
    }
}

private struct OnyxAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.2) : animation, value: value)
    }
}

extension View {
    func onyxAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(OnyxAnimation(animation: animation, value: value))
    }
}
