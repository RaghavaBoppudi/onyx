import SwiftUI
import AVFoundation

struct BottomControlBar: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            CaptureThumbnail(model: model)
            Spacer()
            ShutterButton(model: model)
            Spacer()
            CameraFlipButton(model: model)
            Spacer()
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
    }
}

struct CaptureThumbnail: View {
    @Environment(\.theme) private var theme
    @Environment(\.glyphRotation) private var rotation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .onyxAnimation(Metrics.Motion.glyphRotation, value: rotation)
            .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
        }
        .buttonStyle(ChromePressStyle())
        .disabled(watcher.thumbnail == nil)
        .restricted(model.isAwaitingSecondFrame)
        .accessibilityLabel("Most recent photo")
        .accessibilityHint("Opens Photos")
        .onChange(of: watcher.assetIdentifier) { _, _ in
            scale = reduceMotion ? 1 : Metrics.Thumbnail.popScale
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Metrics.Motion.thumbnailPop) { scale = 1 }
        }
    }
}

struct ShutterButton: View {
    @Environment(\.theme) private var theme
    @State private var isPressed = false

    let model: CameraModel

    var body: some View {
        let isEnabled = model.acceptsShutter

        ZStack {
            Circle()
                .strokeBorder(theme.shutterRing, lineWidth: Metrics.Shutter.ringWidth)
                .frame(width: Metrics.Shutter.outerDiameter, height: Metrics.Shutter.outerDiameter)

            Circle()
                .fill(theme.shutterGradient)
                .frame(width: Metrics.Shutter.diameter, height: Metrics.Shutter.diameter)
                .scaleEffect(isPressed ? Metrics.Shutter.pressedScale : 1)
        }
        .opacity(model.isShutterDimmed ? 0.4 : 1)
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
        .accessibilityAction {
            guard isEnabled else { return }
            Task { await model.capture() }
        }
    }
}

struct CameraFlipButton: View {
    let model: CameraModel

    var body: some View {
        let isFront = model.cameraPosition == .front

        ChromeIcon(
            symbol: Symbols.cameraFlip,
            role: .action,
            isActive: isFront,
            action: { Task { await model.flipCamera() } }
        )
        .restricted(!model.canFlipCamera)
        .accessibilityLabel("Switch camera")
        .accessibilityValue(isFront ? "Front" : "Rear")
    }
}
