import SwiftUI

enum LooksControlState: Equatable {
    case closed(isNonDefaultActive: Bool)
    case browsing
    case awaitingSecondFrame
}

struct BottomControlBar: View {
    let thumbnail: UIImage?
    let thumbnailAssetIdentifier: String?
    let isBusy: Bool
    let isCaptureRestricted: Bool
    let isBrowsingLooks: Bool
    let looksState: LooksControlState
    let glyphRotation: Angle
    let onOpenPhotos: () -> Void
    let onCapture: () -> Void
    let onLooksAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            CaptureThumbnail(
                image: thumbnail,
                assetIdentifier: thumbnailAssetIdentifier,
                rotation: glyphRotation,
                onTap: onOpenPhotos
            )
            .disabled(isCaptureRestricted || isBrowsingLooks)
            .opacity(isBrowsingLooks ? 0 : (isCaptureRestricted ? 0.35 : 1))

            Spacer()

            ShutterButton(isEnabled: !isBusy, action: onCapture)
                .opacity(isBrowsingLooks ? 0 : 1)
                .disabled(isBrowsingLooks)

            Spacer()

            LooksButton(state: looksState, rotation: glyphRotation, action: onLooksAction)
                .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
                .opacity(isBrowsingLooks ? 0 : 1)
                .allowsHitTesting(!isBrowsingLooks)

            Spacer()
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
    }
}

struct CaptureThumbnail: View {
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

struct ShutterButton: View {
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

struct LooksButton: View {
    let state: LooksControlState
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        ChromeIcon(
            symbol: symbol,
            isActive: isFilled,
            tint: tint,
            rotation: rotation,
            action: action
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    @Environment(\.theme) private var theme

    private var symbol: SymbolPair {
        switch state {
        case .closed: Symbols.looks
        case .browsing: Symbols.looks
        case .awaitingSecondFrame: Symbols.cancel
        }
    }

    private var isFilled: Bool {
        switch state {
        case .closed(let isNonDefaultActive): isNonDefaultActive
        case .browsing: false
        case .awaitingSecondFrame: true
        }
    }

    private var tint: Color {
        switch state {
        case .closed(let isNonDefaultActive): isNonDefaultActive ? theme.accent : theme.iconActive
        case .browsing: theme.iconActive
        case .awaitingSecondFrame: theme.accent
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .closed: "Looks"
        case .browsing: "Looks"
        case .awaitingSecondFrame: "Cancel double exposure"
        }
    }

    private var accessibilityValue: String {
        if case .closed(let isNonDefaultActive) = state, isNonDefaultActive {
            return "Active"
        }
        return ""
    }
}
