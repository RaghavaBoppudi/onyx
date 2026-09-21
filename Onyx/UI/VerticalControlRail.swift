import AVFoundation
import SwiftUI

private struct TopGroupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BottomGroupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct VerticalControlRail: View {
    let isGridVisible: Bool
    let isSettingsOpen: Bool
    let flashMode: AVCaptureDevice.FlashMode
    let thumbnail: UIImage?
    let thumbnailAssetIdentifier: String?
    let isBusy: Bool
    let isCaptureRestricted: Bool
    let isBrowsingLooks: Bool
    let looksState: LooksControlState
    let glyphRotation: Angle
    let onToggleGrid: () -> Void
    let onCycleFlash: () -> Void
    let onOpenSettings: () -> Void
    let onOpenPhotos: () -> Void
    let onCapture: () -> Void
    let onLooksAction: () -> Void

    @State private var topGroupHeight: CGFloat = 0
    @State private var bottomGroupHeight: CGFloat = 0

    private var shutterOuterDiameter: CGFloat {
        Metrics.Shutter.diameter + Metrics.Shutter.ringGap * 2
    }

    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height / 2

            let halfSpan = max(
                shutterOuterDiameter / 2 + Metrics.Chrome.railItemSpacing + topGroupHeight,
                shutterOuterDiameter / 2 + Metrics.Chrome.railItemSpacing + bottomGroupHeight
            )
            let available = max(centerY - Metrics.Chrome.railVerticalInset, 1)
            let scale = halfSpan > available ? available / halfSpan : 1

            let topCenterY = centerY - (shutterOuterDiameter / 2 + Metrics.Chrome.railItemSpacing + topGroupHeight / 2) * scale
            let bottomCenterY = centerY + (shutterOuterDiameter / 2 + Metrics.Chrome.railItemSpacing + bottomGroupHeight / 2) * scale

            ZStack {
                topGroup
                    .background(
                        GeometryReader { measureProxy in
                            Color.clear.preference(key: TopGroupHeightKey.self, value: measureProxy.size.height)
                        }
                    )
                    .scaleEffect(scale)
                    .position(x: centerX, y: topCenterY)

                ShutterButton(isEnabled: !isBusy, action: onCapture)
                    .opacity(isBrowsingLooks ? 0 : 1)
                    .disabled(isBrowsingLooks)
                    .scaleEffect(scale)
                    .position(x: centerX, y: centerY)

                bottomGroup
                    .background(
                        GeometryReader { measureProxy in
                            Color.clear.preference(key: BottomGroupHeightKey.self, value: measureProxy.size.height)
                        }
                    )
                    .scaleEffect(scale)
                    .position(x: centerX, y: bottomCenterY)
            }
        }
        .onPreferenceChange(TopGroupHeightKey.self) { topGroupHeight = $0 }
        .onPreferenceChange(BottomGroupHeightKey.self) { bottomGroupHeight = $0 }
    }

    private var topGroup: some View {
        VStack(spacing: Metrics.Chrome.railItemSpacing) {
            ChromeIcon(
                symbol: Symbols.appearance,
                isActive: isSettingsOpen,
                rotation: glyphRotation,
                action: onOpenSettings
            )
            .accessibilityLabel("Appearance")
            .accessibilityValue(isSettingsOpen ? "Open" : "Closed")

            ChromeIcon(
                symbol: Symbols.grid,
                isActive: isGridVisible,
                rotation: glyphRotation,
                action: onToggleGrid
            )
            .accessibilityLabel("Rule of thirds grid")
            .accessibilityValue(isGridVisible ? "On" : "Off")

            ChromeIcon(
                symbol: flashSymbol,
                isActive: flashMode != .off,
                rotation: glyphRotation,
                action: onCycleFlash
            )
            .accessibilityLabel("Flash")
            .accessibilityValue(flashMode == .off ? "Off" : "On")
        }
        .opacity(isBrowsingLooks ? 0 : 1)
        .allowsHitTesting(!isBrowsingLooks)
        .disabled(isCaptureRestricted)
        .opacity(isCaptureRestricted ? 0.35 : 1)
    }

    private var bottomGroup: some View {
        VStack(spacing: Metrics.Chrome.railItemSpacing) {
            LooksButton(state: looksState, rotation: glyphRotation, action: onLooksAction)
                .opacity(looksState == .browsing ? 0 : 1)
                .allowsHitTesting(looksState != .browsing)

            CaptureThumbnail(
                image: thumbnail,
                assetIdentifier: thumbnailAssetIdentifier,
                rotation: glyphRotation,
                onTap: onOpenPhotos
            )
            .disabled(isCaptureRestricted || isBrowsingLooks)
            .opacity(isBrowsingLooks ? 0 : (isCaptureRestricted ? 0.35 : 1))
        }
    }

    private var flashSymbol: SymbolPair {
        switch flashMode {
        case .on: Symbols.flashOn
        case .off, .auto: Symbols.flashOff
        @unknown default: Symbols.flashOff
        }
    }
}
