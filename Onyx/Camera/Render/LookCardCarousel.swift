import SwiftUI

struct LookCardCarousel: View {
    @Environment(\.theme) private var theme

    let looks: [LookKind]
    let boxSize: CGSize
    let onPreview: (LookKind) -> Void
    let onConfirm: (LookKind) -> Void

    @State private var activeIndex: Int

    init(
        looks: [LookKind],
        selectedID: LookKind.ID,
        boxSize: CGSize,
        onPreview: @escaping (LookKind) -> Void,
        onConfirm: @escaping (LookKind) -> Void
    ) {
        self.looks = looks
        self.boxSize = boxSize
        self.onPreview = onPreview
        self.onConfirm = onConfirm
        _activeIndex = State(initialValue: looks.firstIndex(where: { $0.id == selectedID }) ?? 0)
    }

    private var imageRegionHeight: CGFloat {
        boxSize.height - Metrics.LookCarousel.textSpacing - Metrics.LookCarousel.captionHeight
    }
    private var cardWidth: CGFloat {
        boxSize.width - Metrics.LookCarousel.edgeMargin * 2
    }
    private var cardHeight: CGFloat {
        imageRegionHeight - Metrics.LookCarousel.verticalInset * 2
    }
    private var slotStride: CGFloat {
        cardWidth + Metrics.LookCarousel.cardSpacing
    }
    private var currentLook: LookKind {
        looks.indices.contains(activeIndex) ? looks[activeIndex] : (looks.first ?? .standard)
    }

    var body: some View {
        VStack(spacing: Metrics.LookCarousel.textSpacing) {
            ZStack {
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    LookPreviewCard(look: look)
                        .frame(width: cardWidth, height: cardHeight)
                        .offset(x: slotOffset(for: index))
                }
            }
            .frame(width: boxSize.width, height: imageRegionHeight)
            .clipped()
            .contentShape(.rect)
            .gesture(dragGesture)

            VStack(spacing: 4) {
                Text(currentLook.displayName)
                    .font(Typography.lookTitle)
                    .foregroundStyle(theme.iconActive)
                    .lineLimit(1)
                Text(currentLook.summary)
                    .font(Typography.caption)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            }
            .frame(height: Metrics.LookCarousel.captionHeight, alignment: .top)
        }
    }

    private func slotOffset(for index: Int) -> CGFloat {
        CGFloat(index - activeIndex) * slotStride
    }

    private func look(at location: CGPoint) -> LookKind? {
        let center = boxSize.width / 2
        for (index, look) in looks.enumerated() {
            let slotCenter = center + slotOffset(for: index)
            let slotMinX = slotCenter - cardWidth / 2
            let slotMaxX = slotCenter + cardWidth / 2
            if location.x >= slotMinX, location.x <= slotMaxX {
                return look
            }
        }
        return nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                let isTap = abs(horizontal) < Metrics.LensSelector.tapMovementThreshold
                    && abs(vertical) < Metrics.LensSelector.tapMovementThreshold

                if isTap {
                    guard let tapped = look(at: value.startLocation) else { return }
                    if tapped == currentLook {
                        onConfirm(tapped)
                    } else if let index = looks.firstIndex(of: tapped) {
                        withAnimation(.reduceMotionAware(Metrics.Motion.lensPill)) { activeIndex = index }
                        onPreview(tapped)
                    }
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance
                else { return }

                let nextIndex = horizontal < 0 ? activeIndex + 1 : activeIndex - 1
                guard looks.indices.contains(nextIndex) else { return }
                withAnimation(.reduceMotionAware(Metrics.Motion.lensPill)) { activeIndex = nextIndex }
                onPreview(looks[nextIndex])
            }
    }
}

private struct LookPreviewCard: View {
    @Environment(\.theme) private var theme
    let look: LookKind

    var body: some View {
        Group {
            if let uiImage = LookPreviewImages.image(for: look) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.segmentTrack
                    .overlay {
                        Text(look.displayName)
                            .font(Typography.caption)
                            .foregroundStyle(theme.secondary)
                    }
            }
        }
        .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))
    }
}
