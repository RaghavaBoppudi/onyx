import SwiftUI
import AVFoundation

struct StatusControls: View {
    let axis: Axis
    let settings: AppSettings
    let isSettingsOpen: Bool
    let isRestricted: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 0) {
                    flashIcon.frame(maxWidth: .infinity)
                    gridIcon.frame(maxWidth: .infinity)
                    appearanceIcon.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Metrics.Chrome.edgeInset)
                .frame(height: Metrics.Chrome.barHeight)
            } else {
                VStack(spacing: Metrics.Chrome.railItemSpacing) {
                    appearanceIcon
                    gridIcon
                    flashIcon
                }
            }
        }
        .restricted(isRestricted)
    }

    private var appearanceIcon: some View {
        ChromeIcon(
            symbol: Symbols.appearance,
            isActive: isSettingsOpen,
            action: { onOpenSettings() }
        )
        .accessibilityLabel("Appearance")
        .accessibilityValue(isSettingsOpen ? "Open" : "Closed")
    }

    private var gridIcon: some View {
        ChromeIcon(
            symbol: Symbols.grid,
            isActive: settings.isGridVisible,
            action: { toggleGrid() }
        )
        .accessibilityLabel("Rule of thirds grid")
        .accessibilityValue(settings.isGridVisible ? "On" : "Off")
    }

    private var flashIcon: some View {
        ChromeIcon(
            symbol: settings.flashMode == .on ? Symbols.flashOn : Symbols.flashOff,
            isActive: settings.flashMode != .off,
            action: { cycleFlash() }
        )
        .accessibilityLabel("Flash")
        .accessibilityValue(settings.flashMode == .off ? "Off" : "On")
    }

    private func toggleGrid() {
        Haptics.shared.fire(.toggle)
        withAnimation(.reduceMotionAware(Metrics.Motion.gridFade)) { settings.isGridVisible.toggle() }
    }

    private func cycleFlash() {
        Haptics.shared.fire(.toggle)
        settings.cycleFlash()
    }
}
