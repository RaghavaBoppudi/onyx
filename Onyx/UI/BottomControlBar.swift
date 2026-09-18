import AVFoundation
import SwiftUI

struct BottomControlBar: View {
    let thumbnail: UIImage?
    let thumbnailAssetIdentifier: String?
    let flashMode: AVCaptureDevice.FlashMode
    let isBusy: Bool
    let isCaptureRestricted: Bool
    let glyphRotation: Angle
    let onOpenPhotos: () -> Void
    let onCycleFlash: () -> Void
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            CaptureThumbnail(
                image: thumbnail,
                assetIdentifier: thumbnailAssetIdentifier,
                rotation: glyphRotation,
                onTap: onOpenPhotos
            )
            .disabled(isCaptureRestricted)
            .opacity(isCaptureRestricted ? 0.35 : 1)

            Spacer()

            ShutterButton(isEnabled: !isBusy, action: onCapture)

            Spacer()

            ChromeIcon(
                symbol: flashSymbol,
                isActive: flashMode != .off,
                rotation: glyphRotation,
                action: onCycleFlash
            )
            .accessibilityLabel("Flash")
            .accessibilityValue(flashValue)
            .disabled(isCaptureRestricted)
            .opacity(isCaptureRestricted ? 0.35 : 1)

            Spacer()
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
    }

    private var flashSymbol: SymbolPair {
        switch flashMode {
        case .on: Symbols.flashOn
        case .off, .auto: Symbols.flashOff
        @unknown default: Symbols.flashOff
        }
    }

    private var flashValue: String {
        switch flashMode {
        case .on: "On"
        case .off, .auto: "Off"
        @unknown default: "Off"
        }
    }
}

private struct CaptureThumbnail: View {
    @Environment(\.theme) private var theme

    let image: UIImage?
    let assetIdentifier: String?
    let rotation: Angle
    let onTap: () -> Void

    @State private var scale: CGFloat = 1

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image {
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
        .disabled(image == nil)
        .accessibilityLabel("Most recent photo")
        .accessibilityHint("Opens Photos")
        .onChange(of: assetIdentifier) { _, _ in
            scale = Metrics.Thumbnail.popScale
            withAnimation(.reduceMotionAware(Metrics.Motion.thumbnailPop)) { scale = 1 }
        }
    }
}

private struct ShutterButton: View {
    @Environment(\.theme) private var theme
    @State private var isPressed = false

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.shutterRing, lineWidth: Metrics.Shutter.ringWidth)
                .frame(width: outerDiameter, height: outerDiameter)

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
            action()
        })
        .accessibilityLabel("Shutter")
        .accessibilityAddTraits(.isButton)
    }

    private var outerDiameter: CGFloat {
        Metrics.Shutter.diameter + Metrics.Shutter.ringGap * 2
    }
}
