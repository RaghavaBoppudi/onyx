import AVFoundation
import SwiftUI

struct StatusIconRail: View {
    let isGridVisible: Bool
    let isSettingsOpen: Bool
    let flashMode: AVCaptureDevice.FlashMode
    let isBrowsingLooks: Bool
    let isCaptureRestricted: Bool
    let glyphRotation: Angle
    let onToggleGrid: () -> Void
    let onCycleFlash: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
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

    private var flashSymbol: SymbolPair {
        switch flashMode {
        case .on: Symbols.flashOn
        case .off, .auto: Symbols.flashOff
        @unknown default: Symbols.flashOff
        }
    }
}
