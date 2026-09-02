import SwiftUI

enum Typography {
    static func lens(active: Bool) -> Font {
        .system(size: 16, weight: active ? .semibold : .regular)
    }

    static let panelHeader = Font.system(size: 12, weight: .semibold)
    static let caption     = Font.system(size: 13, weight: .regular)
    static let body        = Font.system(size: 16, weight: .regular)
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
    func onyxGlass(in shape: some Shape, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                if let tint {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.interactive(), in: shape)
                }
            } else {
                if let tint {
                    self.glassEffect(.regular.tint(tint), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct SymbolPair {
    let outline: String
    let filled: String
}

enum Symbols {
    static let grid = SymbolPair(outline: "square.grid.3x3", filled: "square.grid.3x3.fill")
    static let settings = SymbolPair(outline: "gearshape", filled: "gearshape.fill")

    static let flashOff = SymbolPair(outline: "bolt.slash", filled: "bolt.slash.fill")
    static let flashOn  = SymbolPair(outline: "bolt", filled: "bolt.fill")

    static let noPermission = "camera.metering.unknown"
}
