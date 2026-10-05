import SwiftUI
import AVFoundation

struct StatusControls: View {
    let axis: Axis
    let settings: AppSettings
    let model: CameraModel

    var body: some View {
        if axis == .horizontal {
            HStack(spacing: 0) {
                flashIcon.frame(maxWidth: .infinity)
                gridIcon.frame(maxWidth: .infinity)
                dualIcon.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Metrics.Chrome.edgeInset)
            .frame(height: Metrics.Chrome.barHeight)
        } else {
            VStack(spacing: Metrics.Chrome.railItemSpacing) {
                dualIcon
                gridIcon
                flashIcon
            }
        }
    }

    private var dualIcon: some View {
        ChromeIcon(
            symbol: Symbols.dual,
            isActive: model.isDualActive,
            action: { toggleDual() }
        )
        .restricted(!model.isDualAvailable || model.isAwaitingSecondFrame)
        .accessibilityLabel("Dual capture")
        .accessibilityValue(model.isDualActive ? "On" : "Off")
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
        .restricted(model.isAwaitingSecondFrame || model.isDualActive)
        .accessibilityLabel("Flash")
        .accessibilityValue(settings.flashMode == .off ? "Off" : "On")
    }

    private func toggleGrid() {
        Haptics.shared.fire(.toggle)
        withAnimation(.reduceMotionAware(Metrics.Motion.gridFade)) { settings.isGridVisible.toggle() }
    }

    private func toggleDual() {
        Haptics.shared.fire(.toggle)
        Task { await model.toggleDual() }
    }

    private func cycleFlash() {
        Haptics.shared.fire(.toggle)
        settings.cycleFlash()
    }
}

struct ModeButton: View {
    @Environment(\.isBrowsingModes) private var isBrowsingModes

    let model: CameraModel
    let action: () -> Void

    var body: some View {
        let isCancel = model.isAwaitingSecondFrame
        let isModified = model.selectedMode != .standard && !isCancel

        PillButton(
            title: isCancel ? "Cancel" : "Mode",
            badge: isModified,
            action: action
        )
        .restricted(model.isDualActive)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ModesIconFrameKey.self,
                    value: isBrowsingModes ? nil : proxy.frame(in: .named(ViewfinderSpace.name))
                )
            }
        }
        .accessibilityLabel(isCancel ? "Cancel double exposure" : "Mode")
        .accessibilityValue(isModified ? model.selectedMode.displayName : "")
    }
}
