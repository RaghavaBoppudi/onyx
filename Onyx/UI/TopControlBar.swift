import AVFoundation
import SwiftUI

struct TopControlBar: View {
    let isGridVisible: Bool
    let isSettingsOpen: Bool
    let flashMode: AVCaptureDevice.FlashMode
    let glyphRotation: Angle
    let onToggleGrid: () -> Void
    let onCycleFlash: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ChromeIcon(
                symbol: flashSymbol,
                isActive: flashMode != .off,
                rotation: glyphRotation,
                action: onCycleFlash
            )
            .accessibilityLabel("Flash")
            .accessibilityValue(flashMode == .off ? "Off" : "On")
            .frame(maxWidth: .infinity)

            ChromeIcon(
                symbol: Symbols.grid,
                isActive: isGridVisible,
                rotation: glyphRotation,
                action: onToggleGrid
            )
            .accessibilityLabel("Rule of thirds grid")
            .accessibilityValue(isGridVisible ? "On" : "Off")
            .frame(maxWidth: .infinity)

            ChromeIcon(
                symbol: Symbols.appearance,
                isActive: isSettingsOpen,
                rotation: glyphRotation,
                action: onOpenSettings
            )
            .accessibilityLabel("Appearance")
            .accessibilityValue(isSettingsOpen ? "Open" : "Closed")
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
        .frame(height: Metrics.Chrome.barHeight)
    }

    private var flashSymbol: SymbolPair {
        switch flashMode {
        case .on: Symbols.flashOn
        case .off, .auto: Symbols.flashOff
        @unknown default: Symbols.flashOff
        }
    }
}
