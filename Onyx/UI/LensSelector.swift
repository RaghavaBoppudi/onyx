import SwiftUI

struct LensSelector: View {
    @Environment(\.theme) private var theme
    @Namespace private var glassNamespace

    let lenses: [Lens]
    let selectedID: String?
    let onSelect: (Lens) -> Void

    @State private var pendingID: String?

    private var displayedID: String? { pendingID ?? selectedID }

    private var activeIndex: Int? { lenses.firstIndex { $0.id == displayedID } }

    private var totalWidth: CGFloat {
        guard !lenses.isEmpty else { return 0 }
        return CGFloat(lenses.count) * Metrics.LensSelector.itemWidth
            + CGFloat(lenses.count - 1) * Metrics.LensSelector.itemSpacing
    }

    var body: some View {
        Group {
            if selectedID == nil {
                Color.clear
                    .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
            } else {
                dial
                    .onChange(of: selectedID) { _, _ in
                        pendingID = nil
                    }
            }
        }
    }

    private var dial: some View {
        ZStack {
            GlassEffectContainer {
                ZStack {
                    ForEach(lenses) { lens in
                        Group {
                            if lens.id == displayedID {
                                Color.clear
                                    .onyxGlass(in: .capsule, interactive: true)
                                    .glassEffectID("lens.active", in: glassNamespace)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: lens))
                    }
                }
            }
            .animation(Metrics.Motion.lensPill, value: displayedID)

            ZStack {
                ForEach(lenses) { lens in
                    let isActive = lens.id == displayedID

                    Text(lens.label)
                        .font(Typography.lens(active: isActive))
                        .foregroundStyle(isActive ? theme.accent : theme.secondary)
                        .fontWeight(isActive ? .bold : nil)
                        .monospacedDigit()
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: lens))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(lens.label) lens")
                        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(lens) }
                }
            }
            .animation(.reduceMotionAware(Metrics.Motion.lensPill), value: displayedID)
        }
        .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
        .contentShape(.rect)
        .gesture(dialGesture)
    }

    private func slotOffset(for lens: Lens) -> CGFloat {
        guard let active = activeIndex, let index = lenses.firstIndex(of: lens) else { return 0 }
        return CGFloat(index - active) * (Metrics.LensSelector.itemWidth + Metrics.LensSelector.itemSpacing)
    }

    private func lens(atX x: CGFloat) -> Lens? {
        lenses.first {
            abs(x - (totalWidth / 2 + slotOffset(for: $0))) <= Metrics.LensSelector.itemWidth / 2
        }
    }

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let tapLimit = Metrics.LensSelector.tapMovementThreshold

                if abs(horizontal) < tapLimit, abs(vertical) < tapLimit {
                    if let tapped = lens(atX: value.startLocation.x) { select(tapped) }
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance,
                      let currentIndex = activeIndex
                else { return }

                let nextIndex = horizontal < 0 ? currentIndex + 1 : currentIndex - 1
                guard lenses.indices.contains(nextIndex) else { return }

                select(lenses[nextIndex])
            }
    }

    private func select(_ lens: Lens) {
        guard lens.id != displayedID else { return }
        pendingID = lens.id
        onSelect(lens)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if pendingID == lens.id { pendingID = nil }
        }
    }
}
