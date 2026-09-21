import SwiftUI

enum Typography {
    static func lens(active: Bool) -> Font {
        .body.weight(active ? .semibold : .regular)
    }

    static let panelHeader = Font.footnote.weight(.semibold)
    static let caption     = Font.caption
    static let body        = Font.body
    static let lookTitle   = Font.title2.weight(.semibold)
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "SYSTEM"
        case .light:  "LIGHT"
        case .dark:   "DARK"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    func resolved(against system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
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
}

struct SymbolPair {
    let outline: String
    let filled: String
}

enum Symbols {
    static let grid = SymbolPair(outline: "square.grid.3x3", filled: "square.grid.3x3.fill")
    static let appearance = SymbolPair(outline: "circle.lefthalf.filled", filled: "circle.lefthalf.filled.inverse")

    static let flashOff = SymbolPair(outline: "bolt.slash", filled: "bolt.slash.fill")
    static let flashOn  = SymbolPair(outline: "bolt", filled: "bolt.fill")

    static let looks = SymbolPair(outline: "camera.filters", filled: "camera.filters")
    static let cancel = SymbolPair(outline: "xmark.circle", filled: "xmark.circle.fill")

    static let noPermission = "camera.metering.unknown"
}
