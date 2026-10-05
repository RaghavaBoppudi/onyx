import SwiftUI
import AVFoundation

struct StatusControls: View {
    let axis: Axis
    let settings: AppSettings
    let model: CameraModel
    let onModesAction: () -> Void

    var body: some View {
        if axis == .horizontal {
            HStack(spacing: 0) {
                flashIcon.frame(maxWidth: .infinity)
                gridIcon.frame(maxWidth: .infinity)
                ModeButton(model: model, action: onModesAction).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Metrics.Chrome.edgeInset)
            .frame(height: Metrics.Chrome.barHeight)
        } else {
            VStack(spacing: Metrics.Chrome.railItemSpacing) {
                ModeButton(model: model, action: onModesAction)
                gridIcon
                flashIcon
            }
        }
    }

    private var gridIcon: some View {
        ChromeIcon(
            symbol: Symbols.grid,
            isActive: settings.isGridVisible,
            action: { toggleGrid() }
        )
        .restricted(model.isAwaitingSecondFrame)
        .accessibilityLabel("Rule of thirds grid")
        .accessibilityValue(settings.isGridVisible ? "On" : "Off")
    }

    private var flashIcon: some View {
        ChromeIcon(
            symbol: settings.flashMode == .on ? Symbols.flashOn : Symbols.flashOff,
            isActive: settings.flashMode != .off,
            action: { cycleFlash() }
        )
        .restricted(model.isAwaitingSecondFrame || model.selectedMode.isDual)
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

struct ModeButton: View {
    @Environment(\.theme) private var theme

    let model: CameraModel
    let action: () -> Void

    var body: some View {
        let isCancel = model.isAwaitingSecondFrame
        let isActive = isCancel || model.selectedMode != .standard

        ChromeIcon(
            symbol: isCancel ? Symbols.cancel : Symbols.modes,
            isActive: isActive,
            tint: isActive ? theme.accent : theme.iconActive,
            action: action
        )
        .accessibilityLabel(isCancel ? "Cancel double exposure" : "Modes")
        .accessibilityValue(isActive && !isCancel ? "Active" : "")
    }
}
