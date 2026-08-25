//  ShutterButton.swift
//  The only element in the app that uses the accent colour.

import SwiftUI

struct ShutterButton: View {
    @Environment(\.theme) private var theme
    @State private var isPressed = false

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(theme.shutterRing, lineWidth: Metrics.Shutter.ringWidth)
                .frame(width: outerDiameter, height: outerDiameter)

            Circle()
                .fill(theme.accent)
                .frame(width: Metrics.Shutter.diameter, height: Metrics.Shutter.diameter)
                .scaleEffect(isPressed ? Metrics.Shutter.pressedScale : 1)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(.circle)
        .animation(Metrics.Motion.shutterPress, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            // Gate the arm haptic on isEnabled, but always update isPressed — the
            // button's disabled state can change in the gap between press-down and
            // release (isCapturing flips true the instant the first tap fires), and
            // if the release edge is swallowed by an isEnabled guard, isPressed
            // never resets. That was the stuck-depressed bug on the first shot:
            // the release that should have cleared it arrived after isEnabled had
            // already gone false.
            if pressing, isEnabled, !isPressed { Haptics.shared.fire(.shutterArm) }
            isPressed = pressing
        }, perform: {
            guard isEnabled else { return }
            action()
        })
        .accessibilityLabel("Shutter")
        .accessibilityAddTraits(.isButton)
    }

    private var outerDiameter: CGFloat {
        Metrics.Shutter.diameter + Metrics.Shutter.ringGap * 2
    }
}
