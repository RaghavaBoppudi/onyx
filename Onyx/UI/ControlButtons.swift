import AVFoundation
import SwiftUI

struct StatusIconButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let symbol: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isActive ? Color.onyxAccent : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .animation(.smooth, value: symbol)
                .rotatesWithDevice()
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }
}

struct StatusIconToggle: View {
    let title: String
    let symbol: String
    let activeSymbol: String
    @Binding var isOn: Bool

    var body: some View {
        StatusIconButton(
            title: title,
            symbol: isOn ? activeSymbol : symbol,
            isActive: isOn
        ) {
            isOn.toggle()
        }
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: isOn)
    }
}

struct GlassCircleButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let symbol: String
    var size: CGFloat = 47
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.primary)
                .rotatesWithDevice()
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }
}

struct CameraFlipButton: View {
    let model: CameraModel

    var body: some View {
        GlassCircleButton(
            title: "Switch camera",
            symbol: "arrow.triangle.2.circlepath.camera"
        ) {
            Task { await model.flipCamera() }
        }
        .disabled(!model.canFlipCamera)
        .accessibilityValue(model.cameraPosition == .front ? "Front" : "Rear")
    }
}
