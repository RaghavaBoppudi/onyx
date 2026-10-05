import SwiftUI

struct LookCardCarousel: View {
    @Environment(\.theme) private var theme

    let looks: [LookKind]
    let onConfirm: (LookKind) -> Void

    @State private var activeIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(looks: [LookKind], selected: LookKind, onConfirm: @escaping (LookKind) -> Void) {
        self.looks = looks
        self.onConfirm = onConfirm
        _activeIndex = State(initialValue: looks.firstIndex(of: selected) ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let card = cardSize(in: screen)
            let step = card.width + Metrics.LookCarousel.cardSpacing
            let current = looks[activeIndex]

            VStack(spacing: Metrics.LookCarousel.captionSpacing) {
                HStack(spacing: Metrics.LookCarousel.cardSpacing) {
                    ForEach(looks) { look in
                        Image(look.previewAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: card.width, height: card.height)
                            .clipShape(.rect(cornerRadius: Metrics.LookCarousel.cornerRadius))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    }
                }
                .offset(x: (screen.width - card.width) / 2 - CGFloat(activeIndex) * step + dragOffset)
                .frame(width: screen.width, height: card.height, alignment: .leading)

                VStack(spacing: 4) {
                    Text(current.displayName)
                        .font(Typography.lookTitle)
                        .foregroundStyle(theme.iconActive)
                    Text(current.summary)
                        .font(Typography.caption)
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)
                }
                .frame(width: card.width)
                .overlay(alignment: .bottom) {
                    pageDots
                        .offset(y: Metrics.LookCarousel.dotsHeight + Metrics.LookCarousel.dotsGap)
                }
                .allowsHitTesting(false)
            }
            .frame(width: screen.width, height: screen.height)
            .contentShape(.rect)
            .gesture(dragGesture(card: card, screenWidth: screen.width))
        }
        .ignoresSafeArea()
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(looks.indices, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? theme.iconActive : theme.iconInactive)
                    .frame(width: index == activeIndex ? 7 : 5, height: index == activeIndex ? 7 : 5)
            }
        }
        .frame(height: Metrics.LookCarousel.dotsHeight)
        .animation(.reduceMotionAware(Metrics.Motion.lensPill), value: activeIndex)
    }

    private func cardSize(in screen: CGSize) -> CGSize {
        let aspect = Metrics.Viewfinder.aspect(isLandscape: screen.width > screen.height)
        let width = min(
            screen.width * Metrics.LookCarousel.widthFraction,
            screen.height * Metrics.LookCarousel.heightFraction * aspect
        )
        return CGSize(width: width, height: width / aspect)
    }

    private func dragGesture(card: CGSize, screenWidth: CGFloat) -> some Gesture {
        let step = card.width + Metrics.LookCarousel.cardSpacing

        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                let translation = value.translation
                guard abs(translation.width) > abs(translation.height) else { return }
                let isAtEdge = (translation.width > 0 && activeIndex == 0)
                    || (translation.width < 0 && activeIndex == looks.count - 1)
                dragOffset = isAtEdge ? translation.width * 0.3 : translation.width
            }
            .onEnded { value in
                let translation = value.translation
                let tapLimit = Metrics.LensSelector.tapMovementThreshold

                if abs(translation.width) < tapLimit, abs(translation.height) < tapLimit {
                    handleTap(at: value.startLocation.x, cardWidth: card.width, screenWidth: screenWidth)
                    return
                }

                var target = activeIndex
                if abs(translation.width) > abs(translation.height) {
                    let projected = value.predictedEndTranslation.width
                    let threshold = step * Metrics.LookCarousel.swipeThreshold
                    if projected < -threshold {
                        target += 1
                    } else if projected > threshold {
                        target -= 1
                    }
                }
                settle(on: min(max(target, 0), looks.count - 1))
            }
    }

    private func handleTap(at x: CGFloat, cardWidth: CGFloat, screenWidth: CGFloat) {
        let cardMinX = (screenWidth - cardWidth) / 2

        if x < cardMinX {
            settle(on: max(activeIndex - 1, 0))
        } else if x > cardMinX + cardWidth {
            settle(on: min(activeIndex + 1, looks.count - 1))
        } else {
            dragOffset = 0
            onConfirm(looks[activeIndex])
        }
    }

    private func settle(on index: Int) {
        if index != activeIndex { Haptics.shared.fire(.selection) }
        withAnimation(.reduceMotionAware(Metrics.Motion.lensSwitch)) {
            activeIndex = index
            dragOffset = 0
        }
    }
}
