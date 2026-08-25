//  Theme.swift
//  Semantic tokens. Views read these; they never touch Palette.

import SwiftUI

struct Theme: Sendable {
    let scheme: ColorScheme

    var accent: Color          { Palette.accent.resolve(scheme) }
    var canvas: Color          { Palette.canvas.resolve(scheme) }
    var panel: Color           { Palette.panel.resolve(scheme) }
    var segmentTrack: Color    { Palette.segmentTrack.resolve(scheme) }
    var segmentThumb: Color    { Palette.segmentThumb.resolve(scheme) }
    var primary: Color         { Palette.primary.resolve(scheme) }
    var secondary: Color       { Palette.secondary.resolve(scheme) }
    var inactive: Color        { Palette.inactive.resolve(scheme) }
    var onThumb: Color         { Palette.onThumb.resolve(scheme) }
    var onAccent: Color        { Palette.onAccent.resolve(scheme) }
    var iconActive: Color      { Palette.iconActive.resolve(scheme) }
    var iconInactive: Color    { Palette.iconInactive.resolve(scheme) }
    var viewfinderVoid: Color  { Palette.viewfinderVoid.resolve(scheme) }
    var gridLine: Color        { Palette.gridLine.resolve(scheme) }
    var shutterRing: Color     { Palette.shutterRing.resolve(scheme) }
    var shutterBlink: Color    { Palette.shutterBlink.resolve(scheme) }
    var thumbnailBorder: Color { Palette.thumbnailBorder.resolve(scheme) }
    var warning: Color         { Palette.warning.resolve(scheme) }
    var error: Color           { Palette.error.resolve(scheme) }

    /// One call site for every chrome glyph.
    func icon(active: Bool) -> Color { active ? iconActive : iconInactive }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(scheme: .dark)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func themed(_ scheme: ColorScheme) -> some View {
        environment(\.theme, Theme(scheme: scheme))
    }
}
