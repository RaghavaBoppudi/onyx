import AVFoundation
import SwiftUI

struct ModeCardCarousel: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let modes: [CaptureMode]
    let position: AVCaptureDevice.Position
    let onConfirm: (CaptureMode) -> Void
    let onDismiss: () -> Void

    @State private var activeID: String?
    @State private var dismissOffset: CGFloat = 0
    @State private var axisLock: Axis?

    init(
        modes: [CaptureMode],
        selected: CaptureMode,
        position: AVCaptureDevice.Position,
        onConfirm: @escaping (CaptureMode) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.modes = modes
        self.position = position
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _activeID = State(initialValue: selected.id)
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
            .ignoresSafeArea()
            .simultaneousGesture(dismissGesture)
            .onChange(of: activeID) { old, new in
                guard old != nil, new != nil, old != new else { return }
                Haptics.shared.fire(.selection)
            }
    }

    private var carousel: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let card = cardSize(in: screen)

            ZStack {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                VStack(spacing: Metrics.ModeCarousel.captionSpacing) {
                    cards(card: card, screenWidth: screen.width)
                    caption(card: card)
                }
                .frame(width: screen.width, height: screen.height)
                .offset(y: dismissOffset)
                .scaleEffect(reduceMotion ? 1 : 1 - dismissProgress * 0.08)
                .opacity(1 - dismissProgress * 0.6)
            }
            .frame(width: screen.width, height: screen.height)
        }
    }

    private func cards(card: CGSize, screenWidth: CGFloat) -> some View {
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

        return VStack(spacing: 4) {
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
        .frame(width: card.width)
        .overlay(alignment: .bottom) {
            pageDots
                .offset(y: Metrics.ModeCarousel.dotsHeight + Metrics.ModeCarousel.dotsGap)
        }
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
