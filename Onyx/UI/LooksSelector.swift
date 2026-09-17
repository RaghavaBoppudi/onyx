import SwiftUI

struct LooksSelector: View {
    @Environment(\.theme) private var theme
    @Namespace private var glassNamespace

    let looks: [LookKind]
    let selectedID: LookKind.ID
    let onSelect: (LookKind) -> Void

    private var activeIndex: Int? { looks.firstIndex(where: { $0.id == selectedID }) }

    private var totalWidth: CGFloat {
        guard !looks.isEmpty else { return 0 }
        return CGFloat(looks.count) * Metrics.LensSelector.itemWidth
            + CGFloat(looks.count - 1) * Metrics.LensSelector.itemSpacing
    }

    var body: some View {
        ZStack {
            GlassEffectContainer {
                ZStack {
                    ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                        let isActive = look.id == selectedID

                        Group {
                            if isActive {
                                Color.clear
                                    .onyxGlass(in: .capsule, interactive: true, tint: theme.canvas.opacity(0.3))
                                    .glassEffectID("looks.active", in: glassNamespace)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: index))
                    }
                }
            }
            .animation(Metrics.Motion.lensPill, value: selectedID)

            ZStack {
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    let isActive = look.id == selectedID

                    Text(look.displayName)
                        .font(Typography.lens(active: isActive))
                        .foregroundStyle(isActive ? theme.accent : theme.secondary)
                        .fontWeight(isActive ? .bold : nil)
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: index))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(look.displayName) look")
                        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onSelect(look) }
                }
            }
            .animation(Metrics.Motion.lensPill, value: selectedID)
        }
        .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
        .contentShape(.rect)
        .gesture(dialGesture)
    }

    private func slotOffset(for index: Int) -> CGFloat {
        guard let activeIdx = activeIndex else { return 0 }
        return CGFloat(index - activeIdx) * (Metrics.LensSelector.itemWidth + Metrics.LensSelector.itemSpacing)
    }

    private func look(at location: CGPoint) -> LookKind? {
        let dialCenter = totalWidth / 2
        for (index, look) in looks.enumerated() {
            let slotCenter = dialCenter + slotOffset(for: index)
            let slotMinX = slotCenter - Metrics.LensSelector.itemWidth / 2
            let slotMaxX = slotCenter + Metrics.LensSelector.itemWidth / 2
            if location.x >= slotMinX, location.x <= slotMaxX {
                return look
            }
        }
        return nil
    }

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                let isTap = abs(horizontal) < Metrics.LensSelector.tapMovementThreshold
                    && abs(vertical) < Metrics.LensSelector.tapMovementThreshold

                if isTap {
                    if let tapped = look(at: value.startLocation) {
                        onSelect(tapped)
                    }
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance
                else { return }

                guard let currentIndex = activeIndex else { return }

                let nextIndex = horizontal < 0 ? currentIndex + 1 : currentIndex - 1
                guard looks.indices.contains(nextIndex) else { return }

                onSelect(looks[nextIndex])
            }
    }
}
