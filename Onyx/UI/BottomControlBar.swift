import SwiftUI

struct BottomControlBar: View {
    let model: CameraModel
    let onLooksAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            CaptureThumbnail(model: model)
            Spacer()
            ShutterButton(model: model)
            Spacer()
            LooksButton(model: model, action: onLooksAction)
            Spacer()
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
    }
}

struct CaptureThumbnail: View {
    @Environment(\.theme) private var theme
    @Environment(\.glyphRotation) private var rotation

    let model: CameraModel

    @State private var scale: CGFloat = 1

    var body: some View {
        let watcher = model.recentPhoto

        Button { model.openPhotosApp() } label: {
            ZStack {
                if let image = watcher.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    theme.segmentTrack
                }
            }
            .frame(width: Metrics.Thumbnail.size, height: Metrics.Thumbnail.size)
            .clipShape(.circle)
            .overlay {
                Circle()
                    .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
            }
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .animation(.reduceMotionAware(Metrics.Motion.glyphRotation), value: rotation)
            .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
        }
        .buttonStyle(.plain)
        .disabled(watcher.thumbnail == nil)
        .restricted(model.isAwaitingSecondFrame)
        .accessibilityLabel("Most recent photo")
        .accessibilityHint("Opens Photos")
        .onChange(of: watcher.assetIdentifier) { _, _ in
            scale = Metrics.Thumbnail.popScale
            withAnimation(.reduceMotionAware(Metrics.Motion.thumbnailPop)) { scale = 1 }
        }
    }
}

struct ShutterButton: View {
    @Environment(\.theme) private var theme
    @State private var isPressed = false

    let model: CameraModel

    var body: some View {
        let isEnabled = !model.isBusy

        ZStack {
            Circle()
                .strokeBorder(theme.shutterRing, lineWidth: Metrics.Shutter.ringWidth)
                .frame(width: Metrics.Shutter.outerDiameter, height: Metrics.Shutter.outerDiameter)

            Circle()
                .fill(theme.shutterGradient)
                .frame(width: Metrics.Shutter.diameter, height: Metrics.Shutter.diameter)
                .scaleEffect(isPressed ? Metrics.Shutter.pressedScale : 1)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(.circle)
        .animation(Metrics.Motion.shutterPress, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            if pressing, isEnabled, !isPressed { Haptics.shared.fire(.shutterArm) }
            isPressed = pressing
        }, perform: {
            guard isEnabled else { return }
            Task { await model.capture() }
        })
        .accessibilityLabel("Shutter")
        .accessibilityAddTraits(.isButton)
    }
}

struct LooksButton: View {
    @Environment(\.theme) private var theme

    let model: CameraModel
    let action: () -> Void

    var body: some View {
        let isCancel = model.isAwaitingSecondFrame
        let isActive = isCancel || model.selectedLook != .standard

        ChromeIcon(
            symbol: isCancel ? Symbols.cancel : Symbols.looks,
            isActive: isActive,
            tint: isActive ? theme.accent : theme.iconActive,
            action: action
        )
        .accessibilityLabel(isCancel ? "Cancel double exposure" : "Looks")
        .accessibilityValue(isActive && !isCancel ? "Active" : "")
    }
}
