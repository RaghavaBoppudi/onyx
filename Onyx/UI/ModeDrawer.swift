import SwiftUI

struct ModeDrawer: View {
    let model: CameraModel
    var axis: Axis = .horizontal
    let onClose: () -> Void

    private enum Layout {
        static let tileWidth: CGFloat = 76
        static let tileSpacing: CGFloat = 12
        static let inset: CGFloat = 16
        static let horizontalWidth = CGFloat(CaptureMode.allCases.count) * tileWidth
            + CGFloat(CaptureMode.allCases.count - 1) * tileSpacing
            + inset * 2
        static let verticalWidth: CGFloat = 264
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            switch axis {
            case .horizontal:
                tiles
                summary
            case .vertical:
                list
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: axis == .horizontal ? Layout.horizontalWidth : Layout.verticalWidth)
        .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: .rect(cornerRadius: 32))
        .accessibilityAction(.escape) { onClose() }
    }

    private var header: some View {
        ZStack {
            Text(model.selectedMode.displayName.uppercased())
                .font(.subheadline.weight(.medium))
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
        .padding(.horizontal, Layout.inset)
    }

    private var tiles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Layout.tileSpacing) {
                ForEach(CaptureMode.allCases) { mode in
                    tile(for: mode)
                }
            }
            .padding(.horizontal, Layout.inset)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var list: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView(.vertical) { rows }
                .scrollIndicators(.hidden)
        }
    }

    private var rows: some View {
        VStack(spacing: 10) {
            ForEach(CaptureMode.allCases) { mode in
                row(for: mode)
            }
        }
        .padding(.horizontal, Layout.inset)
    }

    private func preview(for mode: CaptureMode, isSelected: Bool) -> some View {
        Image(mode.previewAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 96)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white, lineWidth: isSelected ? 2.5 : 0)
            }
    }

    private func tile(for mode: CaptureMode) -> some View {
        let isSelected = mode == model.selectedMode

        return Button {
            Task { await model.setMode(mode) }
        } label: {
            VStack(spacing: 6) {
                preview(for: mode, isSelected: isSelected)

                Text(mode.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
            }
            .frame(width: Layout.tileWidth)
            .opacity(isSelected ? 1 : 0.85)
        }
        .buttonStyle(PressScaleButtonStyle())
        .animation(.smooth(duration: 0.2), value: isSelected)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func row(for mode: CaptureMode) -> some View {
        let isSelected = mode == model.selectedMode

        return Button {
            Task { await model.setMode(mode) }
        } label: {
            HStack(spacing: 12) {
                preview(for: mode, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
                    Text(mode.summary(for: model.cameraPosition))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .opacity(isSelected ? 1 : 0.9)
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
