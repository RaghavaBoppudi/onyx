import SwiftUI

struct LensPicker: View {
    let model: CameraModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var tickIndex = 0

    private enum Geometry {
        static let slot: CGFloat = 56
        static let height: CGFloat = 44
        static let pill = CGSize(width: 62, height: 36)
        static let visibleSlots: CGFloat = 3
        static let commitDistance: CGFloat = 20
        static let rubberBand: CGFloat = 0.55
    }

    private var lenses: [Lens] { model.visibleLenses }
    private var maxIndex: Int { max(lenses.count - 1, 0) }

    private var activeIndex: Int {
        let id = model.pendingLensID ?? model.selectedLens?.id
        return lenses.firstIndex { $0.id == id } ?? 0
    }

    private var restingOffset: CGFloat { -CGFloat(activeIndex) * Geometry.slot }
    private var stripOffset: CGFloat { restingOffset + dragOffset }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(lenses.enumerated()), id: \.element.id) { index, lens in
                    label(for: lens, at: index)
                }
            }
            .offset(x: stripOffset + CGFloat(maxIndex) * Geometry.slot / 2)

            Color.clear
                .frame(width: Geometry.pill.width, height: Geometry.pill.height)
                .glassEffect(.clear, in: .capsule)
                .allowsHitTesting(false)
        }
        .frame(width: Geometry.slot * Geometry.visibleSlots, height: Geometry.height)
        .mask(edgeFade)
        .contentShape(.rect)
        .gesture(drag)
        .sensoryFeedback(.selection, trigger: tickIndex) { _, _ in isDragging }
        .onChange(of: activeIndex, initial: true) { _, index in
            if !isDragging { tickIndex = index }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lens")
        .accessibilityValue(lenses.indices.contains(activeIndex) ? lenses[activeIndex].label : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(min(activeIndex + 1, maxIndex))
            case .decrement: commit(max(activeIndex - 1, 0))
            @unknown default: break
            }
        }
    }

    private func label(for lens: Lens, at index: Int) -> some View {
        let distance = CGFloat(index) * Geometry.slot + stripOffset
        let proximity = max(0, 1 - abs(distance) / Geometry.slot)

        return Text(lens.label)
            .font(.subheadline.weight(proximity > 0.5 ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(1 + 0.12 * proximity)
            .opacity(0.55 + 0.45 * proximity)
            .frame(width: Geometry.slot, height: Geometry.height)
            .contentShape(.rect)
            .onTapGesture { commit(index) }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                isDragging = true
                dragOffset = rubberBanded(value.translation.width)
                tickIndex = nearestIndex(to: stripOffset)
            }
            .onEnded { value in
                let current = stripOffset
                let target = neighbor(for: value.predictedEndTranslation.width)
                let remaining = -CGFloat(target) * Geometry.slot - current
                let relativeVelocity = abs(remaining) > 1 ? value.velocity.width / remaining : 0
                commit(target, initialVelocity: relativeVelocity)
            }
    }

    private func commit(_ target: Int, initialVelocity: CGFloat = 0) {
        guard lenses.indices.contains(target) else { return }

        let animation: Animation = reduceMotion
            ? .smooth(duration: 0.2)
            : .interpolatingSpring(
                Spring(response: 0.32, dampingRatio: initialVelocity == 0 ? 1 : 0.86),
                initialVelocity: initialVelocity
            )

        withAnimation(animation) {
            dragOffset = 0
            isDragging = false
            if target != activeIndex { model.requestLens(lenses[target]) }
        }
    }

    private func neighbor(for predictedTranslation: CGFloat) -> Int {
        let step: Int
        if predictedTranslation <= -Geometry.commitDistance {
            step = 1
        } else if predictedTranslation >= Geometry.commitDistance {
            step = -1
        } else {
            step = 0
        }
        return min(max(activeIndex + step, 0), maxIndex)
    }

    private func nearestIndex(to offset: CGFloat) -> Int {
        let raw = Int((-offset / Geometry.slot).rounded())
        return min(max(raw, max(activeIndex - 1, 0)), min(activeIndex + 1, maxIndex))
    }

    private func rubberBanded(_ translation: CGFloat) -> CGFloat {
        let lower = -CGFloat(min(activeIndex + 1, maxIndex)) * Geometry.slot
        let upper = -CGFloat(max(activeIndex - 1, 0)) * Geometry.slot
        let raw = restingOffset + translation

        let bounded: CGFloat
        if raw > upper {
            bounded = upper + resistance(raw - upper)
        } else if raw < lower {
            bounded = lower - resistance(lower - raw)
        } else {
            bounded = raw
        }
        return bounded - restingOffset
    }

    private func resistance(_ overshoot: CGFloat) -> CGFloat {
        let dimension = Geometry.slot
        let constant = Geometry.rubberBand
        return (overshoot * dimension * constant) / (dimension + constant * overshoot)
    }
}
