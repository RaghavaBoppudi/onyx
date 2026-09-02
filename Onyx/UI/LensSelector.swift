import SwiftUI

struct LensSelector: View {
    @Environment(\.theme) private var theme
    @Namespace private var glassNamespace

    let lenses: [Lens]
    let selectedID: String?
    let onSelect: (Lens) -> Void

    @State private var pendingID: String?

    private var displayedID: String? { pendingID ?? selectedID }
    private var activeIndex: Int? { lenses.firstIndex(where: { $0.id == displayedID }) }

    private var totalWidth: CGFloat {
        guard !lenses.isEmpty else { return 0 }
        return CGFloat(lenses.count) * Metrics.LensSelector.itemWidth
            + CGFloat(lenses.count - 1) * Metrics.LensSelector.itemSpacing
    }

    var body: some View {
        GlassEffectContainer {
            ZStack {
                ForEach(Array(lenses.enumerated()), id: \.element.id) { index, lens in
                    let isActive = lens.id == displayedID
                    let slotOffset = slotOffset(for: index)

                    Text(lens.label)
                        .font(Typography.lens(active: isActive))
                        .foregroundStyle(isActive ? theme.accent : theme.icon(active: false))
                        .fontWeight(isActive ? .bold : nil)
                        .saturation(isActive ? 1.6 : 1)
                        .brightness(isActive ? 0.08 : 0)
                        .monospacedDigit()
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .background {
                            if isActive {
                                Color.clear
                                    .onyxGlass(in: .capsule, style: .clear, interactive: true, tint: .black.opacity(0.3))
                                    .glassEffectID("lens.active", in: glassNamespace)
                            }
                        }
                        .offset(x: slotOffset)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(lens.label) lens")
                        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(lens) }
                }
            }
        }
        .animation(Metrics.Motion.lensPill, value: displayedID)
        .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
        .contentShape(.rect)
        .gesture(dialGesture)
        .onChange(of: selectedID) { _, _ in
            pendingID = nil
        }
    }

    private func slotOffset(for index: Int) -> CGFloat {
        guard let activeIdx = activeIndex else { return 0 }
        return CGFloat(index - activeIdx) * (Metrics.LensSelector.itemWidth + Metrics.LensSelector.itemSpacing)
    }

    private func lens(at location: CGPoint) -> Lens? {
        let dialCenter = totalWidth / 2
        for (index, lens) in lenses.enumerated() {
            let slotCenter = dialCenter + slotOffset(for: index)
            let slotMinX = slotCenter - Metrics.LensSelector.itemWidth / 2
            let slotMaxX = slotCenter + Metrics.LensSelector.itemWidth / 2
            if location.x >= slotMinX, location.x <= slotMaxX {
                return lens
            }
        }
        return nil
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

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                let isTap = abs(horizontal) < Metrics.LensSelector.tapMovementThreshold
                    && abs(vertical) < Metrics.LensSelector.tapMovementThreshold

                if isTap {
                    if let tapped = lens(at: value.startLocation) {
                        select(tapped)
                    }
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance
                else { return }

                guard let currentIndex = activeIndex else { return }

                let nextIndex = horizontal < 0 ? currentIndex + 1 : currentIndex - 1
                guard lenses.indices.contains(nextIndex) else { return }

                select(lenses[nextIndex])
            }
    }
}
