import SwiftUI

struct ModeDrawer: View {
    let model: CameraModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            header
            tiles
            summary
        }
        .padding(.vertical, 16)
        .frame(maxWidth: 520)
        .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: .rect(cornerRadius: 32))
        .accessibilityAction(.escape) { onClose() }
    }

    private var header: some View {
        ZStack {
            Text(model.selectedMode.displayName.uppercased())
                .font(.system(size: 15, weight: .medium))
                .tracking(2)
                .foregroundStyle(Color.white)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.2), value: model.selectedMode)

            HStack {
                StatusIconButton(title: "Back to camera", symbol: "chevron.left") {
                    onClose()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private var tiles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(CaptureMode.allCases) { mode in
                    tile(for: mode)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func tile(for mode: CaptureMode) -> some View {
        let isSelected = mode == model.selectedMode

        return Button {
            Task { await model.setMode(mode) }
        } label: {
            VStack(spacing: 6) {
                Image(mode.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 96)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white, lineWidth: isSelected ? 2.5 : 0)
                    }

                Text(mode.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
            }
            .frame(width: 76)
            .opacity(isSelected ? 1 : 0.85)
        }
        .buttonStyle(PressScaleButtonStyle())
        .animation(.smooth(duration: 0.2), value: isSelected)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var summary: some View {
        Text(model.selectedMode.summary(for: model.cameraPosition))
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .padding(.horizontal, 24)
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.2), value: model.selectedMode)
    }
}
