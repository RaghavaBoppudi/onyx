//  AppearancePanel.swift
//  Glass panel over the viewfinder — the one surface in the app with live content
//  beneath it to refract.
//
//  Cross-fade, not a slide. The panel belongs to the settings button that summoned
//  it; travelling in from the top edge implies it came from somewhere else.

import SwiftUI

struct AppearancePanel: View {
    @Environment(\.theme) private var theme
    @Binding var selection: AppearanceMode

    var body: some View {
        VStack(spacing: Metrics.Panel.padding) {
            Text("APPEARANCE")
                .font(Typography.panelHeader)
                .tracking(1.6)
                .foregroundStyle(theme.secondary)

            SegmentedPicker(selection: $selection)
        }
        .padding(Metrics.Panel.padding + 4)
        .frame(maxWidth: .infinity)
        .onyxGlass(in: .rect(cornerRadius: Metrics.Panel.cornerRadius))
        .transition(.opacity)
    }
}

private struct SegmentedPicker: View {
    @Environment(\.theme) private var theme
    @Namespace private var thumb
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppearanceMode.allCases) { mode in
                let isSelected = mode == selection

                Text(mode.title)
                    .font(Typography.segment)
                    .tracking(0.6)
                    .foregroundStyle(isSelected ? theme.onThumb : theme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.Panel.segmentHeight)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(theme.segmentThumb)
                                .matchedGeometryEffect(id: "segment.thumb", in: thumb)
                        } else {
                            Capsule().fill(theme.segmentTrack)
                        }
                    }
                    .contentShape(.capsule)
                    .onTapGesture {
                        guard !isSelected else { return }
                        Haptics.shared.fire(.selection)
                        withAnimation(Metrics.Motion.lensSwitch) { selection = mode }
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
