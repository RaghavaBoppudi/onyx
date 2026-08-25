//  BottomControlBar.swift
//  Thumbnail · Shutter · Flash.
//
//  Same three centred columns as the top bar. The outer controls sit visually
//  halfway between the screen edge and the shutter rather than against the margins.

import AVFoundation
import SwiftUI

struct BottomControlBar: View {
    let thumbnail: UIImage?
    let thumbnailAssetIdentifier: String?
    let flashMode: AVCaptureDevice.FlashMode
    let isCapturing: Bool
    let glyphRotation: Angle
    let onOpenPhotos: () -> Void
    let onCycleFlash: () -> Void
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            CaptureThumbnail(
                image: thumbnail,
                assetIdentifier: thumbnailAssetIdentifier,
                rotation: glyphRotation,
                onTap: onOpenPhotos
            )
            .frame(maxWidth: .infinity)

            ShutterButton(isEnabled: !isCapturing, action: onCapture)
                .frame(maxWidth: .infinity)

            ChromeIcon(
                symbol: flashSymbol,
                isActive: flashMode != .off,
                rotation: glyphRotation,
                action: onCycleFlash
            )
            .accessibilityLabel("Flash")
            .accessibilityValue(flashValue)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Metrics.Chrome.edgeInset)
    }

    private var flashSymbol: SymbolPair {
        switch flashMode {
        case .on: Symbols.flashOn
        // .auto is a real case of Apple's enum, but cycleFlash() never produces
        // it — this app only ever toggles off/on. Handled the same as any future
        // case Apple might add: fall back to the off glyph.
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
