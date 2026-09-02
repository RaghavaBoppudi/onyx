import SwiftUI

struct TopControlBar: View {
    let isGridVisible: Bool
    let isSettingsOpen: Bool
    let glyphRotation: Angle
    let onToggleGrid: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ChromeIcon(
                symbol: Symbols.grid,
                isActive: isGridVisible,
                rotation: glyphRotation,
                action: onToggleGrid
            )
            .accessibilityLabel("Rule of thirds grid")
            .accessibilityValue(isGridVisible ? "On" : "Off")
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)

            ChromeIcon(
                symbol: Symbols.settings,
                isActive: isSettingsOpen,
                rotation: glyphRotation,
                action: onOpenSettings
            )
            .accessibilityLabel("Appearance")
            .accessibilityValue(isSettingsOpen ? "Open" : "Closed")
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
        .frame(height: Metrics.Chrome.barHeight)
    }
}
