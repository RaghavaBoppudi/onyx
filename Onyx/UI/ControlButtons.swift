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
        .buttonStyle(PressScaleButtonStyle())
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

struct CameraFlipButton: View {
    let model: CameraModel

    var body: some View {
        StatusIconButton(
            title: "Switch camera",
            symbol: "arrow.triangle.2.circlepath.camera"
        ) {
            Task { await model.flipCamera() }
        }
        .frame(width: 48, height: 48)
        .disabled(!model.canFlipCamera)
        .accessibilityValue(model.cameraPosition == .front ? "Front" : "Rear")
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: configuration.isPressed)
    }
}
