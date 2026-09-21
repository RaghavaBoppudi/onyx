import SwiftUI
import UIKit

struct LookCardCarousel: View {
    @Environment(\.theme) private var theme

    let looks: [LookKind]
    let onPreview: (LookKind) -> Void
    let onConfirm: (LookKind) -> Void

    @State private var activeIndex: Int
    @State private var dragTranslation: CGFloat = 0
    @State private var isTransitioning = false

    init(
        looks: [LookKind],
        selectedID: LookKind.ID,
        onPreview: @escaping (LookKind) -> Void,
        onConfirm: @escaping (LookKind) -> Void
    ) {
        self.looks = looks
        self.onPreview = onPreview
        self.onConfirm = onConfirm
        _activeIndex = State(initialValue: looks.firstIndex(where: { $0.id == selectedID }) ?? 0)
    }

    private var currentLook: LookKind {
        looks.indices.contains(activeIndex) ? looks[activeIndex] : (looks.first ?? .standard)
    }

    private var fadeColor: Color {
        theme.scheme == .dark ? Palette.onyx : Palette.alabaster
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let progress = min(max(dragTranslation / width, -1), 1)

            ZStack {
                LookPreviewCard(look: looks[activeIndex])
                    .opacity(1 - abs(progress))

                if progress < 0, looks.indices.contains(activeIndex + 1) {
                    LookPreviewCard(look: looks[activeIndex + 1])
                        .opacity(-progress)
                }
                if progress > 0, looks.indices.contains(activeIndex - 1) {
                    LookPreviewCard(look: looks[activeIndex - 1])
                        .opacity(progress)
                }

                LinearGradient(
                    colors: [.clear, fadeColor.opacity(0.55), fadeColor],
                    startPoint: UnitPoint(x: 0.5, y: 0.35),
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
            .overlay(alignment: .bottom) {
                PageIndicator(count: looks.count, activeIndex: activeIndex, theme: theme)
                    .padding(.horizontal, Metrics.LookCarousel.horizontalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, height * Metrics.LookCarousel.dotsBottomFraction)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentLook.displayName)
                        .font(Typography.lookTitle)
                        .foregroundStyle(theme.iconActive)
                        .lineLimit(1)
                    Text(currentLook.summary)
                        .font(Typography.caption)
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(.horizontal, Metrics.LookCarousel.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, height * Metrics.LookCarousel.captionBottomFraction)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isTransitioning else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                dragTranslation = horizontal
            }
            .onEnded { value in
                guard !isTransitioning else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height

                let isTap = abs(horizontal) < Metrics.LensSelector.tapMovementThreshold
                    && abs(vertical) < Metrics.LensSelector.tapMovementThreshold

                if isTap {
                    withAnimation(.reduceMotionAware(Metrics.Motion.lensPill)) { dragTranslation = 0 }
                    onConfirm(currentLook)
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance else {
                    withAnimation(.reduceMotionAware(Metrics.Motion.lensPill)) { dragTranslation = 0 }
                    return
                }

                let progress = horizontal / width
                let threshold: CGFloat = 0.25

                if progress <= -threshold, activeIndex < looks.count - 1 {
                    commit(direction: 1, width: width)
                } else if progress >= threshold, activeIndex > 0 {
                    commit(direction: -1, width: width)
                } else {
                    withAnimation(.reduceMotionAware(Metrics.Motion.lensPill)) { dragTranslation = 0 }
                }
            }
    }

    private func commit(direction: Int, width: CGFloat) {
        let nextIndex = activeIndex + direction
        guard looks.indices.contains(nextIndex) else { return }

        if UIAccessibility.isReduceMotionEnabled {
            activeIndex = nextIndex
            dragTranslation = 0
            onPreview(looks[nextIndex])
            return
        }

        isTransitioning = true
        withAnimation(Metrics.Motion.lensPill) {
            dragTranslation = CGFloat(-direction) * width
        }

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            activeIndex = nextIndex
            dragTranslation = 0
            isTransitioning = false
            onPreview(looks[nextIndex])
        }
    }
}

private struct PageIndicator: View {
    let count: Int
    let activeIndex: Int
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? theme.iconActive : theme.iconInactive)
                    .frame(width: index == activeIndex ? 7 : 5, height: index == activeIndex ? 7 : 5)
            }
        }
        .animation(.reduceMotionAware(Metrics.Motion.lensPill), value: activeIndex)
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
        .clipped()
    }
}
