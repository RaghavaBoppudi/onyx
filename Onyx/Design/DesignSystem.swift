//  DesignSystem.swift
//  Typography, appearance mode, and the Liquid Glass wrapper — three small,
//  unrelated-to-each-other concerns that each used to have their own file at 17,
//  17, and 29 lines. None of them grows on its own; none of them is reused outside
//  Design/. Colour stays out of here on purpose: Palette and Theme are the two
//  files that answer "what colour is this," and that answer needs to live
//  somewhere findable in one step, not stirred into a junk drawer with fonts.

import SwiftUI

// MARK: - Typography

enum Typography {
    /// Lens factor labels — 0.5x, 1x, 2x.
    static func lens(active: Bool) -> Font {
        .system(size: 16, weight: active ? .semibold : .regular)
    }

    static let panelHeader = Font.system(size: 12, weight: .semibold)
    static let segment     = Font.system(size: 15, weight: .medium)
    static let caption     = Font.system(size: 13, weight: .regular)
    static let body        = Font.system(size: 16, weight: .regular)
}

// MARK: - Appearance mode

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

    /// `nil` means "defer to the system."
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

// MARK: - Liquid Glass

// Glass belongs in chrome that overlays the preview — never on the flat canvas,
// where it has nothing to refract. In Onyx that's only the appearance panel.
extension View {
    /// Apply *after* layout and visual modifiers, never before. Never nest — glass
    /// cannot sample glass.
    @ViewBuilder
    func onyxGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
