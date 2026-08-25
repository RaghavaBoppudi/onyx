//  ChromeIcon.swift
//  Every glyph in the app goes through here: one point size, one weight, one square
//  tap target. Uniform by construction rather than by eye.
//
//  Active state is white (near-black in light mode), never the accent. The accent
//  belongs to the shutter alone so its meaning stays unambiguous.

import SwiftUI

struct ChromeIcon: View {
    @Environment(\.theme) private var theme

    let symbol: SymbolPair
    var isActive: Bool = false
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? symbol.filled : symbol.outline)
                .font(Metrics.Chrome.symbolFont)
                .foregroundStyle(theme.icon(active: isActive))
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(rotation)
                .animation(Metrics.Motion.glyphRotation, value: rotation)
                .frame(width: Metrics.Chrome.tapTarget,
                       height: Metrics.Chrome.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
