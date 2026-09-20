import AVFoundation
import SwiftUI

private struct RailContentHeightKey: PreferenceKey {
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

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let available = max(proxy.size.height - Metrics.Chrome.railVerticalInset * 2, 1)
            let scale = (contentHeight > 0 && contentHeight > available) ? available / contentHeight : 1
            let scaledHeight = contentHeight * scale
            let topOffset = max((proxy.size.height - scaledHeight) / 2, 0)

            stack
                .background(
                    GeometryReader { measureProxy in
                        Color.clear.preference(key: RailContentHeightKey.self, value: measureProxy.size.height)
                    }
                )
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: contentHeight, alignment: .top)
                .position(x: proxy.size.width / 2, y: topOffset + scaledHeight / 2)
        }
        .onPreferenceChange(RailContentHeightKey.self) { contentHeight = $0 }
    }

    @ViewBuilder
    private var stack: some View {
        VStack(spacing: Metrics.Chrome.railItemSpacing) {
            ChromeIcon(
                symbol: flashSymbol,
                isActive: flashMode != .off,
                rotation: glyphRotation,
                action: onCycleFlash
            )
            .accessibilityLabel("Flash")
            .accessibilityValue(flashMode == .off ? "Off" : "On")
            .opacity(isBrowsingLooks ? 0 : 1)
            .allowsHitTesting(!isBrowsingLooks)
            .disabled(isCaptureRestricted)
            .opacity(isCaptureRestricted ? 0.35 : 1)

            ChromeIcon(
                symbol: Symbols.grid,
                isActive: isGridVisible,
                rotation: glyphRotation,
                action: onToggleGrid
            )
            .accessibilityLabel("Rule of thirds grid")
            .accessibilityValue(isGridVisible ? "On" : "Off")
            .opacity(isBrowsingLooks ? 0 : 1)
            .allowsHitTesting(!isBrowsingLooks)
            .disabled(isCaptureRestricted)
            .opacity(isCaptureRestricted ? 0.35 : 1)

            ChromeIcon(
                symbol: Symbols.appearance,
                isActive: isSettingsOpen,
                rotation: glyphRotation,
                action: onOpenSettings
            )
            .accessibilityLabel("Appearance")
            .accessibilityValue(isSettingsOpen ? "Open" : "Closed")
            .opacity(isBrowsingLooks ? 0 : 1)
            .allowsHitTesting(!isBrowsingLooks)
            .disabled(isCaptureRestricted)
            .opacity(isCaptureRestricted ? 0.35 : 1)

            LooksButton(state: looksState, rotation: glyphRotation, action: onLooksAction)
                .opacity(isBrowsingLooks ? 0 : 1)
                .allowsHitTesting(!isBrowsingLooks)

            ShutterButton(isEnabled: !isBusy, action: onCapture)
                .opacity(isBrowsingLooks ? 0 : 1)
                .disabled(isBrowsingLooks)

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
