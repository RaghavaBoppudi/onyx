//  CaptureThumbnail.swift
//  The library's most recent photo, springing into place whenever a new one takes
//  over — from Onyx, from the system Camera, from anywhere.
//
//  Pops on `assetIdentifier` changing, not on the image changing. `RecentPhotoWatcher`
//  delivers a low-quality preview first and a better one shortly after for the same
//  photo (progressive delivery) — that second, better image arriving should not
//  replay the arrival animation, since nothing new actually arrived from the
//  user's point of view. The identifier is what changed; the animation follows it.

import SwiftUI

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
            .animation(Metrics.Motion.glyphRotation, value: rotation)
            .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
        .accessibilityLabel("Most recent photo")
        .accessibilityHint("Opens Photos")
        .onChange(of: assetIdentifier) { _, _ in
            scale = Metrics.Thumbnail.popScale
            withAnimation(Metrics.Motion.thumbnailPop) { scale = 1 }
        }
    }
}
