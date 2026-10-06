import SwiftUI

struct CaptureThumbnail: View {
    let model: CameraModel

    var body: some View {
        let watcher = model.recentPhoto

        Button {
            model.openPhotosApp()
        } label: {
            ZStack {
                if let image = watcher.thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .id(watcher.assetIdentifier)
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                } else {
                    Color(.secondarySystemFill)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(.separator, lineWidth: 1)
            }
            .overlay {
                if model.isDeveloping {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: .circle)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.2), value: model.isDeveloping)
            .animation(.spring(response: 0.34, dampingFraction: 0.75), value: watcher.assetIdentifier)
            .rotatesWithDevice()
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(model.isAwaitingSecondFrame)
        .accessibilityLabel("Most recent photo")
        .accessibilityValue(model.isDeveloping ? "Saving" : "")
        .accessibilityHint("Opens Photos")
    }
}
