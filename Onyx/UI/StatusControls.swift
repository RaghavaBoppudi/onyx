import SwiftUI
import AVFoundation

struct StatusControls: View {
    @Bindable var settings: AppSettings
    let axis: Axis
    let model: CameraModel
    let onShowModes: () -> Void

    private enum Item: Hashable {
        case flash, grid, modes, dual, location
    }

    private var items: [Item] {
        let ordered: [Item] = model.isJournalist ? [.flash, .location] : [.flash, .grid, .modes, .dual]
        return axis == .horizontal ? ordered : ordered.reversed()
    }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 28))
            : AnyLayout(VStackLayout(spacing: 12))

        layout {
            ForEach(items, id: \.self) { item in
                control(for: item)
            }
        }
        .frame(maxWidth: axis == .horizontal ? .infinity : nil)
        .frame(height: axis == .horizontal ? 64 : nil)
        .animation(.smooth, value: model.isJournalist)
    }

    @ViewBuilder
    private func control(for item: Item) -> some View {
        switch item {
        case .flash:
            StatusIconToggle(
                title: "Flash",
                symbol: "bolt.slash",
                activeSymbol: "bolt.fill",
                isOn: flashBinding
            )
            .disabled(model.isAwaitingSecondFrame || model.isDualActive)
        case .grid:
            StatusIconToggle(
                title: "Grid",
                symbol: "square.grid.3x3",
                activeSymbol: "square.grid.3x3.fill",
                isOn: $settings.isGridVisible
            )
            .disabled(model.isAwaitingSecondFrame)
        case .modes:
            modesButton
        case .dual:
            StatusIconToggle(
                title: "Dual capture",
                symbol: "pip",
                activeSymbol: "pip.fill",
                isOn: dualBinding
            )
            .disabled(!model.isDualAvailable || model.isAwaitingSecondFrame)
        case .location:
            StatusIconToggle(
                title: "Location",
                symbol: "location",
                activeSymbol: "location.fill",
                isOn: locationBinding
            )
        }
    }

    private var modesButton: some View {
        let isCancel = model.isAwaitingSecondFrame
        let isModified = model.selectedMode != .standard && !isCancel

        return StatusIconButton(
            title: isCancel ? "Cancel double exposure" : "Mode",
            symbol: isCancel ? "xmark" : "camera.filters",
            isActive: isModified
        ) {
            if isCancel {
                model.cancelDoubleExposureSequence()
            } else {
                onShowModes()
            }
        }
        .disabled(model.isDualActive)
        .accessibilityValue(isModified ? model.selectedMode.displayName : "")
    }

    private var flashBinding: Binding<Bool> {
        Binding(
            get: { settings.flashMode != .off },
            set: { settings.flashMode = $0 ? .on : .off }
        )
    }

    private var dualBinding: Binding<Bool> {
        Binding(
            get: { model.isDualActive },
            set: { _ in Task { await model.toggleDual() } }
        )
    }

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { settings.geotagsPhotos },
            set: { model.setGeotagging($0) }
        )
    }
}
