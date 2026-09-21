import SwiftUI

struct SelectorDial<Item: Identifiable & Equatable>: View {
    @Environment(\.theme) private var theme
    @Namespace private var glassNamespace

    let items: [Item]
    let selectedID: Item.ID?
    let accessibilityNoun: String
    let glassNamespaceID: String
    let label: (Item) -> String
    let onSelect: (Item) -> Void

    private var activeIndex: Int? { items.firstIndex(where: { $0.id == selectedID }) }

    private var totalWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        return CGFloat(items.count) * Metrics.LensSelector.itemWidth
            + CGFloat(items.count - 1) * Metrics.LensSelector.itemSpacing
    }

    var body: some View {
        ZStack {
            GlassEffectContainer {
                ZStack {
                    ForEach(items) { item in
                        let isActive = item.id == selectedID

                        Group {
                            if isActive {
                                Color.clear
                                    .onyxGlass(in: .capsule, interactive: true)
                                    .glassEffectID(glassNamespaceID, in: glassNamespace)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: item))
                    }
                }
            }
            .animation(Metrics.Motion.lensPill, value: selectedID)

            ZStack {
                ForEach(items) { item in
                    let isActive = item.id == selectedID

                    Text(label(item))
                        .font(Typography.lens(active: isActive))
                        .foregroundStyle(isActive ? theme.accent : theme.secondary)
                        .fontWeight(isActive ? .bold : nil)
                        .monospacedDigit()
                        .frame(width: Metrics.LensSelector.itemWidth,
                               height: Metrics.LensSelector.pillHeight)
                        .offset(x: slotOffset(for: item))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(label(item)) \(accessibilityNoun)")
                        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onSelect(item) }
                }
            }
            .animation(.reduceMotionAware(Metrics.Motion.lensPill), value: selectedID)
        }
        .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
        .contentShape(.rect)
        .gesture(dialGesture)
    }

    private func slotOffset(for item: Item) -> CGFloat {
        guard let activeIdx = activeIndex, let index = items.firstIndex(of: item) else { return 0 }
        return CGFloat(index - activeIdx) * (Metrics.LensSelector.itemWidth + Metrics.LensSelector.itemSpacing)
    }

    private func item(at location: CGPoint) -> Item? {
        let dialCenter = totalWidth / 2
        for item in items {
            let slotCenter = dialCenter + slotOffset(for: item)
            let slotMinX = slotCenter - Metrics.LensSelector.itemWidth / 2
            let slotMaxX = slotCenter + Metrics.LensSelector.itemWidth / 2
            if location.x >= slotMinX, location.x <= slotMaxX {
                return item
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
                    if let tapped = item(at: value.startLocation) {
                        onSelect(tapped)
                    }
                    return
                }

                guard abs(horizontal) > abs(vertical) * Metrics.LensSelector.swipeHorizontalDominance
                else { return }

                guard let currentIndex = activeIndex else { return }

                let nextIndex = horizontal < 0 ? currentIndex + 1 : currentIndex - 1
                guard items.indices.contains(nextIndex) else { return }

                onSelect(items[nextIndex])
            }
    }
}
