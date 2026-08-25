//  LensSelector.swift
//  Discrete optics, not a zoom slider.

import SwiftUI

struct LensSelector: View {
    @Environment(\.theme) private var theme
    @Namespace private var indicator

    let lenses: [Lens]
    let selectedID: String?
    let onSelect: (Lens) -> Void

    var body: some View {
        HStack(spacing: Metrics.LensSelector.itemSpacing) {
            ForEach(lenses) { lens in
                let isActive = lens.id == selectedID

                VStack(spacing: Metrics.LensSelector.dotSpacing) {
                    Group {
                        if isActive {
                            Circle()
                                .fill(theme.iconActive)
                                .matchedGeometryEffect(id: "lens.dot", in: indicator)
                        } else {
                            Circle().fill(.clear)
                        }
                    }
                    .frame(width: Metrics.LensSelector.dotSize,
                           height: Metrics.LensSelector.dotSize)

                    Text(lens.label)
                        .font(Typography.lens(active: isActive))
                        .foregroundStyle(theme.icon(active: isActive))
                        .monospacedDigit()
                }
                .frame(width: Metrics.LensSelector.itemWidth)
                .padding(.vertical, Metrics.LensSelector.verticalHitSlop)
                .contentShape(.rect)
                .onTapGesture { onSelect(lens) }
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
                .accessibilityLabel("\(lens.label) lens")
            }
        }
        .animation(Metrics.Motion.lensSwitch, value: selectedID)
    }
}
