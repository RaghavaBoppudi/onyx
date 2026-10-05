import SwiftUI
import UIKit

enum Typography {
    static func lens(active: Bool) -> Font {
        .body.weight(active ? .semibold : .regular)
    }

    static let panelHeader = Font.footnote.weight(.semibold)
    static let caption     = Font.caption
    static let body        = Font.body
    static let lookTitle   = Font.title2.weight(.semibold)
}

struct SymbolPair {
    let outline: String
    let filled: String
}

enum Symbols {
    static let grid = SymbolPair(outline: "square.grid.3x3", filled: "square.grid.3x3.fill")

    static let flashOff = SymbolPair(outline: "bolt.slash", filled: "bolt.slash.fill")
    static let flashOn  = SymbolPair(outline: "bolt", filled: "bolt.fill")

    static let modes = SymbolPair(outline: "camera.filters", filled: "camera.filters")
    static let cancel = SymbolPair(outline: "xmark.circle", filled: "xmark.circle.fill")
    static let cameraFlip = SymbolPair(
        outline: "arrow.triangle.2.circlepath.camera",
        filled: "arrow.triangle.2.circlepath.camera.fill"
    )

    static let noPermission = "camera.metering.unknown"
}

extension EnvironmentValues {
    @Entry var glyphRotation: Angle = .zero
}

extension Animation {
    static func reduceMotionAware(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }
}

extension View {
    @ViewBuilder
    func onyxGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if interactive {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.glassEffect(.regular, in: shape)
        }
    }

    func restricted(_ isRestricted: Bool) -> some View {
        disabled(isRestricted).opacity(isRestricted ? 0.35 : 1)
    }
}
