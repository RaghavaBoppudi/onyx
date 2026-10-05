import SwiftUI

struct ModeCardCarousel: View {
    @Environment(\.theme) private var theme

    let modes: [CaptureMode]
    let onConfirm: (CaptureMode) -> Void

    @State private var activeIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(modes: [CaptureMode], selected: CaptureMode, onConfirm: @escaping (CaptureMode) -> Void) {
        self.modes = modes
        self.onConfirm = onConfirm
        _activeIndex = State(initialValue: modes.firstIndex(of: selected) ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let card = cardSize(in: screen)
            let step = card.width + Metrics.ModeCarousel.cardSpacing
            let current = modes[activeIndex]

            VStack(spacing: Metrics.ModeCarousel.captionSpacing) {
                HStack(spacing: Metrics.ModeCarousel.cardSpacing) {
                    ForEach(modes) { mode in
                        Image(mode.previewAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: card.width, height: card.height)
                            .clipShape(.rect(cornerRadius: Metrics.ModeCarousel.cornerRadius))
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
                        .offset(y: Metrics.ModeCarousel.dotsHeight + Metrics.ModeCarousel.dotsGap)
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
            ForEach(modes.indices, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? theme.iconActive : theme.iconInactive)
                    .frame(width: index == activeIndex ? 7 : 5, height: index == activeIndex ? 7 : 5)
            }
        }
        .frame(height: Metrics.ModeCarousel.dotsHeight)
        .animation(.reduceMotionAware(Metrics.Motion.lensPill), value: activeIndex)
    }

    private func cardSize(in screen: CGSize) -> CGSize {
        let aspect = Metrics.Viewfinder.aspect(isLandscape: screen.width > screen.height)
        let width = min(
            screen.width * Metrics.ModeCarousel.widthFraction,
            screen.height * Metrics.ModeCarousel.heightFraction * aspect
        )
        return CGSize(width: width, height: width / aspect)
    }

    private func dragGesture(card: CGSize, screenWidth: CGFloat) -> some Gesture {
        let step = card.width + Metrics.ModeCarousel.cardSpacing

        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                let translation = value.translation
                guard abs(translation.width) > abs(translation.height) else { return }
                let isAtEdge = (translation.width > 0 && activeIndex == 0)
                    || (translation.width < 0 && activeIndex == modes.count - 1)
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
                    let threshold = step * Metrics.ModeCarousel.swipeThreshold
                    if projected < -threshold {
                        target += 1
                    } else if projected > threshold {
                        target -= 1
                    }
                }
                settle(on: min(max(target, 0), modes.count - 1))
            }
    }

    private func handleTap(at x: CGFloat, cardWidth: CGFloat, screenWidth: CGFloat) {
        let cardMinX = (screenWidth - cardWidth) / 2

        if x < cardMinX {
            settle(on: max(activeIndex - 1, 0))
        } else if x > cardMinX + cardWidth {
            settle(on: min(activeIndex + 1, modes.count - 1))
        } else {
            dragOffset = 0
            onConfirm(modes[activeIndex])
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
