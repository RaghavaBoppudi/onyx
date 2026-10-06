import SwiftUI

struct LensSelector: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lenses: [Lens]
    let selectedID: String?
    let pendingID: String?
    let onSelect: (Lens) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var pressedID: String?

    private var itemWidth: CGFloat { Metrics.LensSelector.itemWidth }
    private var pillHeight: CGFloat { Metrics.LensSelector.pillHeight }
    private var step: CGFloat { Metrics.LensSelector.itemWidth + Metrics.LensSelector.itemSpacing }
    private var committedID: String? { pendingID ?? selectedID }
    private var committedIndex: Int? { lenses.firstIndex { $0.id == committedID } }

    private var previewIndex: Int? {
        guard let index = committedIndex else { return nil }
        guard isDragging else { return index }
        let shifted = index - Int((dragOffset / step).rounded())
        return min(max(shifted, 0), lenses.count - 1)
    }

    private var previewID: String? {
        previewIndex.map { lenses[$0].id }
    }

    private var totalWidth: CGFloat {
        guard !lenses.isEmpty else { return 0 }
        return CGFloat(lenses.count) * itemWidth
            + CGFloat(lenses.count - 1) * Metrics.LensSelector.itemSpacing
    }

    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : Metrics.Motion.lensPill
    }

    var body: some View {
        Group {
            if selectedID == nil {
                Color.clear
                    .frame(width: totalWidth, height: pillHeight)
            } else {
                dial
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var dial: some View {
        ZStack {
            Capsule()
                .fill(theme.pillFill)
                .overlay {
                    Capsule()
                        .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
                }
                .frame(width: itemWidth, height: pillHeight)

            ForEach(lenses) { lens in
                label(for: lens)
            }
        }
        .frame(width: totalWidth, height: pillHeight)
        .contentShape(.rect)
        .gesture(dialGesture)
        .onyxAnimation(Metrics.Motion.lensPill, value: committedID)
    }

    private func label(for lens: Lens) -> some View {
        let isActive = lens.id == previewID
        let isSelected = lens.id == committedID

        return Text(lens.label)
            .font(Typography.lens(active: isActive))
            .foregroundStyle(isActive ? theme.iconActive : theme.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(lens.id == pressedID ? 0.94 : 1)
            .frame(width: itemWidth, height: pillHeight)
            .offset(x: slotOffset(for: lens) + dragOffset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(lens.label) lens")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { commit(lens) }
    }

    private func slotOffset(for lens: Lens) -> CGFloat {
        guard let active = committedIndex, let index = lenses.firstIndex(of: lens) else { return 0 }
        return CGFloat(index - active) * step
    }

    private func lens(atX x: CGFloat) -> Lens? {
        lenses.first {
            abs(x - (totalWidth / 2 + slotOffset(for: $0))) <= itemWidth / 2
        }
    }

    private func rubberband(_ overshoot: CGFloat) -> CGFloat {
        let constant: CGFloat = 0.55
        return (overshoot * step * constant) / (step + constant * abs(overshoot))
    }

    private func constrained(_ translation: CGFloat, index: Int) -> CGFloat {
        let upper = CGFloat(index) * step
        let lower = -CGFloat(lenses.count - 1 - index) * step

        if translation > upper { return upper + rubberband(translation - upper) }
        if translation < lower { return lower - rubberband(lower - translation) }
        return translation
    }

    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let width = value.translation.width
                let height = value.translation.height
                let limit = Metrics.LensSelector.tapMovementThreshold

                if !isDragging {
                    let isHorizontal = abs(width) > limit
                        && abs(width) > abs(height) * Metrics.LensSelector.swipeHorizontalDominance

                    guard isHorizontal else {
                        let isStill = abs(width) < limit && abs(height) < limit
                        pressedID = isStill ? lens(atX: value.startLocation.x)?.id : nil
                        return
                    }
                    isDragging = true
                    pressedID = nil
                }

                guard let index = committedIndex else { return }
                let adjusted = width - (width > 0 ? limit : -limit)
                let previous = previewIndex
                dragOffset = constrained(adjusted, index: index)
                if previewIndex != previous { Haptics.shared.fire(.selection) }
            }
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                let limit = Metrics.LensSelector.tapMovementThreshold
                pressedID = nil

                guard isDragging else {
                    if abs(width) < limit, abs(height) < limit, let tapped = lens(atX: value.startLocation.x) {
                        commit(tapped)
                    }
                    return
                }

                guard let index = committedIndex else {
                    isDragging = false
                    dragOffset = 0
                    return
                }

                let projected = value.predictedEndTranslation.width
                let adjusted = projected - (projected > 0 ? limit : -limit)
                let target = min(max(index - Int((adjusted / step).rounded()), 0), lenses.count - 1)

                withAnimation(settleAnimation) {
                    isDragging = false
                    dragOffset = 0
                    if lenses[target].id != committedID { onSelect(lenses[target]) }
                }
            }
    }

    private func commit(_ lens: Lens) {
        guard lens.id != committedID else { return }
        withAnimation(settleAnimation) { onSelect(lens) }
    }
}
