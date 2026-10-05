import SwiftUI

struct Theme: Sendable {

    private static let onyx = Color.hex(0x0A0A0A)
    private static let alabaster = Color.hex(0xE5E4E2)
    private static let blueSlate = Color.hex(0x536878)

    var accent: Color          { Self.blueSlate }
    var canvas: Color          { Self.onyx }
    var secondary: Color       { Self.alabaster.opacity(0.6) }
    var iconActive: Color      { Self.alabaster }
    var iconInactive: Color    { Self.alabaster.opacity(0.4) }
    var viewfinderVoid: Color  { Self.onyx }
    var gridLine: Color        { Self.alabaster.opacity(0.34) }
    var shutterRing: Color     { Self.alabaster }
    var shutterBlink: Color    { Self.onyx }
    var thumbnailBorder: Color { Self.alabaster.opacity(0.22) }
    var segmentTrack: Color    { Self.alabaster.opacity(0.14) }

    var shutterGradient: LinearGradient {
        LinearGradient(
            colors: [Self.onyx, Self.blueSlate, Self.alabaster],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = Theme()
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
