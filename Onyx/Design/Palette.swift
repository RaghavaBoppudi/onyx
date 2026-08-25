//  Palette.swift
//  Onyx — THE colour file. Every colour literal lives here and nowhere else.
//  No view may declare a Color. Views read Theme; Theme reads Palette.

import SwiftUI

enum Palette {

    // MARK: Brand
    /// Shutter only. Chrome icons never use the accent — an active toggle reads
    /// white so the accent stays unambiguous: it means "this takes the picture".
    static let accent = Duo(light: .hex(0xD6F03C), dark: .hex(0xD6F03C))

    // MARK: Surfaces
    static let canvas = Duo(light: .hex(0xF7F7EC), dark: .hex(0x2C2C2C))
    static let panel  = Duo(light: Color.hex(0xFFFFFF).opacity(0.55),
                            dark:  Color.hex(0x3A3A3A).opacity(0.72))
    static let segmentTrack = Duo(light: Color.hex(0x000000).opacity(0.10),
                                  dark:  Color.hex(0x000000).opacity(0.22))
    static let segmentThumb = Duo(light: .hex(0xFFFFFF), dark: .hex(0xFFFFFF))

    // MARK: Content
    static let primary   = Duo(light: .hex(0x0A0A0A), dark: .hex(0xF2F2F2))
    static let secondary = Duo(light: .hex(0x6E6E73), dark: .hex(0x9A9A9E))
    static let inactive  = Duo(light: .hex(0xA8A8AD), dark: .hex(0x8A8A8E))
    static let onThumb   = Duo(light: .hex(0x0A0A0A), dark: .hex(0x0A0A0A))
    static let onAccent  = Duo(light: .hex(0x0A0A0A), dark: .hex(0x0A0A0A))

    // MARK: Chrome icons — one pair, used by every glyph in the app.
    static let iconActive   = Duo(light: .hex(0x0A0A0A), dark: .hex(0xFFFFFF))
    static let iconInactive = Duo(light: .hex(0xA8A8AD), dark: .hex(0x8A8A8E))

    // MARK: Viewfinder
    static let viewfinderVoid = Duo(light: .hex(0x000000), dark: .hex(0x000000))
    static let gridLine = Duo(light: Color.hex(0xFFFFFF).opacity(0.42),
                              dark:  Color.hex(0xFFFFFF).opacity(0.34))
    static let shutterRing = Duo(light: .hex(0xD8D8D0), dark: .hex(0x555555))

    /// Shutter confirmation overlay. Dark, not white — a blink, not a flash.
    static let shutterBlink = Duo(light: .hex(0x000000), dark: .hex(0x000000))
    static let thumbnailBorder = Duo(light: Color.hex(0x000000).opacity(0.18),
                                     dark:  Color.hex(0xFFFFFF).opacity(0.22))

    // MARK: Status
    static let warning = Duo(light: .hex(0xE0761B), dark: .hex(0xFF9F45))
    static let error   = Duo(light: .hex(0xC7362B), dark: .hex(0xFF6B5E))
}

struct Duo: Sendable {
    let light: Color
    let dark: Color
    func resolve(_ scheme: ColorScheme) -> Color { scheme == .dark ? dark : light }
}

extension Color {
    static func hex(_ value: UInt32) -> Color {
        Color(.sRGB,
              red:   Double((value >> 16) & 0xFF) / 255,
              green: Double((value >>  8) & 0xFF) / 255,
              blue:  Double( value        & 0xFF) / 255,
              opacity: 1)
    }
}
