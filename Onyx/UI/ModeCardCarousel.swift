import AVFoundation
import SwiftUI

struct ModeCardCarousel: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var captionTextHeight: CGFloat = 64

    let modes: [CaptureMode]
    let position: AVCaptureDevice.Position
    let topInset: CGFloat
    let avoiding: CGRect?
    let onConfirm: (CaptureMode) -> Void
    let onDismiss: () -> Void

    @Binding var activeID: String?
    @State private var dismissOffset: CGFloat = 0
    @State private var axisLock: Axis?
    @State private var isPositioned = false

    init(
        modes: [CaptureMode],
        activeID: Binding<String?>,
        position: AVCaptureDevice.Position,
        topInset: CGFloat,
        avoiding: CGRect?,
        onConfirm: @escaping (CaptureMode) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.modes = modes
        self.position = position
        self.topInset = topInset
        self.avoiding = avoiding
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _activeID = activeID
    }

    private var activeIndex: Int {
        modes.firstIndex { $0.id == activeID } ?? 0
    }

    private var dismissProgress: CGFloat {
        min(max(dismissOffset / Metrics.ModeCarousel.dismissTravel, 0), 1)
    }

    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Metrics.Motion.modeSettle
    }

    var body: some View {
        carousel
            .simultaneousGesture(dismissGesture)
            .onChange(of: activeID) { old, new in
                guard old != nil, new != nil, old != new else { return }
                Haptics.shared.fire(.selection)
            }
    }

    private var carousel: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let origin = proxy.frame(in: .named(ViewfinderSpace.name)).origin
            let fit = contentFit(screen: screen, origin: origin)

            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                VStack(spacing: Metrics.ModeCarousel.captionSpacing) {
                    cards(card: fit.card, screenWidth: screen.width)
                    caption(card: fit.card)
                }
                .frame(width: screen.width)
                .offset(y: fit.top + dismissOffset)
                .scaleEffect(reduceMotion ? 1 : 1 - dismissProgress * 0.08)
                .opacity(1 - dismissProgress * 0.6)
            }
            .frame(width: screen.width, height: screen.height, alignment: .top)
        }
    }

    private struct Fit {
        let card: CGSize
        let top: CGFloat
    }

    private func contentFit(screen: CGSize, origin: CGPoint) -> Fit {
        let preferred = cardSize(in: screen)
        let aspect = Metrics.Viewfinder.aspect(isLandscape: screen.width > screen.height)
        let chrome = Metrics.ModeCarousel.captionSpacing
            + captionTextHeight
            + Metrics.ModeCarousel.dotsGap
            + Metrics.ModeCarousel.dotsHeight

        let topBound = max(
            topInset + Metrics.ModeCarousel.avoidanceGap,
            screen.height * Metrics.ModeCarousel.topClearanceFraction
        )

        var bottomBound = screen.height - Metrics.ModeCarousel.edgeMargin
        if let avoiding {
            let obstacle = avoiding.offsetBy(dx: -origin.x, dy: -origin.y)
            let columnMinX = (screen.width - preferred.width) / 2
            let columnMaxX = (screen.width + preferred.width) / 2
            if obstacle.maxX > columnMinX, obstacle.minX < columnMaxX {
                bottomBound = min(bottomBound, obstacle.minY - Metrics.ModeCarousel.avoidanceGap)
            }
        }

        let available = max(bottomBound - topBound, 0)
        let cardHeight = min(
            preferred.height,
            max(available - chrome, Metrics.ModeCarousel.minimumCardHeight)
        )
        let card = CGSize(width: cardHeight * aspect, height: cardHeight)

        let blockHeight = card.height + chrome
        let centered = (screen.height - blockHeight) / 2
        let top = min(max(centered, topBound), max(bottomBound - blockHeight, topBound))

        return Fit(card: card, top: top)
    }

    private func cards(card: CGSize, screenWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Metrics.ModeCarousel.cardSpacing) {
                    ForEach(modes) { mode in
                        Button { tap(mode) } label: { cardImage(mode, size: card) }
                            .buttonStyle(CardPressStyle())
                            .id(mode.id)
                            .scrollTransition(.interactive, axis: .horizontal) { [reduceMotion] content, phase in
                                content
                                    .scaleEffect(reduceMotion ? 1 : 1 - (1 - Metrics.ModeCarousel.neighborScale) * min(abs(phase.value), 1))
                                    .opacity(1 - (1 - Metrics.ModeCarousel.neighborOpacity) * min(abs(phase.value), 1))
                            }
                            .accessibilityLabel(mode.displayName)
                            .accessibilityHint(mode.summary(for: position).replacingOccurrences(of: "\n", with: " "))
                            .accessibilityAddTraits(mode.id == activeID ? .isSelected : [])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $activeID, anchor: .center)
            .contentMargins(.horizontal, (screenWidth - card.width) / 2, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(height: card.height)
            .opacity(isPositioned ? 1 : 0)
            .onAppear { restoreScroll(proxy) }
        }
    }

    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let id = activeID, id != modes.first?.id else {
            isPositioned = true
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(id, anchor: .center)
            }
            isPositioned = true
        }
    }

    private func cardImage(_ mode: CaptureMode, size: CGSize) -> some View {
        Image(mode.previewAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Metrics.ModeCarousel.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.ModeCarousel.cornerRadius)
                    .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
            }
    }

    private func caption(card: CGSize) -> some View {
        let current = modes[activeIndex]

        return VStack(spacing: Metrics.ModeCarousel.dotsGap) {
            VStack(spacing: 4) {
                Text(current.displayName)
                    .font(Typography.lookTitle)
                    .foregroundStyle(theme.iconActive)
                    .contentTransition(.opacity)
                Text(current.summary(for: position))
                    .font(Typography.caption)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .contentTransition(.opacity)
            }
            pageDots
        }
        .frame(width: card.width)
        .onyxAnimation(.smooth(duration: 0.2), value: activeID)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    }

    private func cardSize(in screen: CGSize) -> CGSize {
        let aspect = Metrics.Viewfinder.aspect(isLandscape: screen.width > screen.height)
        let width = min(
            screen.width * Metrics.ModeCarousel.widthFraction,
            screen.height * Metrics.ModeCarousel.heightFraction * aspect
        )
        return CGSize(width: width, height: width / aspect)
    }

    private func tap(_ mode: CaptureMode) {
        if mode.id == activeID {
            onConfirm(mode)
        } else {
            withAnimation(settleAnimation) { activeID = mode.id }
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: Metrics.LensSelector.tapMovementThreshold)
            .onChanged { value in
                if axisLock == nil {
                    axisLock = abs(value.translation.height) > abs(value.translation.width) ? .vertical : .horizontal
                }
                guard axisLock == .vertical else { return }
                dismissOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                defer { axisLock = nil }
                guard axisLock == .vertical else { return }

                let threshold = Metrics.ModeCarousel.dismissDistance
                if value.translation.height > threshold || value.predictedEndTranslation.height > threshold * 2 {
                    onDismiss()
                } else {
                    withAnimation(settleAnimation) { dismissOffset = 0 }
                }
            }
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
