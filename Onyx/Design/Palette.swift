import SwiftUI

enum Palette {
    static let onyx = Color.hex(0x0A0A0A)
    static let blueSlate = Color.hex(0x536878)
    static let alabaster = Color.hex(0xE5E4E2)

    static let accent = Duo(light: blueSlate, dark: blueSlate)

    static let canvas = Duo(light: alabaster, dark: onyx)

    static let secondary = Duo(light: onyx.opacity(0.6), dark: alabaster.opacity(0.6))

    static let iconActive   = Duo(light: onyx, dark: alabaster)
    static let iconInactive = Duo(light: onyx.opacity(0.4), dark: alabaster.opacity(0.4))

    static let viewfinderVoid = Duo(light: onyx, dark: onyx)
    static let gridLine = Duo(light: alabaster.opacity(0.42), dark: alabaster.opacity(0.34))
    static let shutterRing = Duo(light: onyx, dark: alabaster)
    static let shutterBlink = Duo(light: onyx, dark: onyx)
    static let thumbnailBorder = Duo(light: onyx.opacity(0.18), dark: alabaster.opacity(0.22))
    static let segmentTrack = Duo(light: onyx.opacity(0.10), dark: alabaster.opacity(0.14))
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
