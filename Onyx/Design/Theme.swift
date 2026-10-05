import SwiftUI

struct Theme: Sendable {
    let scheme: ColorScheme

    private static let onyx = Color.hex(0x0A0A0A)
    private static let alabaster = Color.hex(0xE5E4E2)
    private static let blueSlate = Color.hex(0x536878)

    private var isDark: Bool { scheme == .dark }
    private var ink: Color { isDark ? Self.alabaster : Self.onyx }

    var accent: Color          { Self.blueSlate }
    var canvas: Color          { isDark ? Self.onyx : Self.alabaster }
    var secondary: Color       { ink.opacity(0.6) }
    var iconActive: Color      { ink }
    var iconInactive: Color    { ink.opacity(0.4) }
    var viewfinderVoid: Color  { Self.onyx }
    var gridLine: Color        { Self.alabaster.opacity(isDark ? 0.34 : 0.42) }
    var shutterRing: Color     { ink }
    var shutterBlink: Color    { Self.onyx }
    var thumbnailBorder: Color { ink.opacity(isDark ? 0.22 : 0.18) }
    var segmentTrack: Color    { ink.opacity(isDark ? 0.14 : 0.10) }

    var shutterGradient: LinearGradient {
        LinearGradient(
            colors: [Self.onyx, Self.blueSlate, Self.alabaster],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = Theme(scheme: .dark)
}

extension View {
    func themed(_ scheme: ColorScheme) -> some View {
        environment(\.theme, Theme(scheme: scheme))
    }
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
