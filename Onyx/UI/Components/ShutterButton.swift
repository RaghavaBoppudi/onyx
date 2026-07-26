import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {}) {
            SwiftUI.Color.clear
        }
        .buttonStyle(ShutterButtonStyle(action: action))
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    let action: () -> Void
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Base Tier
            Circle()
                .fill(Theme.Color.Shutter.gradient)
                .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
                .overlay(
                    Circle()
                        .stroke(Theme.Color.Shutter.strokeBase, lineWidth: 1.0)
                )
                .shadow(color: Theme.Color.background.opacity(0.7), radius: 6, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
                .animation(Theme.Physics.shutterBase, value: configuration.isPressed)
            
            // Middle Tier
            Circle()
                .fill(Theme.Color.Shutter.gradient)
                .frame(width: Theme.Layout.Shutter.midSize, height: Theme.Layout.Shutter.midSize)
                .overlay(
                    Circle()
                        .stroke(Theme.Color.Shutter.strokeMid, lineWidth: 1.0)
                )
                .shadow(color: Theme.Color.background.opacity(0.5), radius: 4, x: 0, y: 2)
                .scaleEffect(configuration.isPressed ? 0.80 : 1.0)
                .animation(Theme.Physics.shutterMid, value: configuration.isPressed)
            
            // Top Tier
            Circle()
                .fill(Theme.Color.Shutter.gradient)
                .frame(width: Theme.Layout.Shutter.topSize, height: Theme.Layout.Shutter.topSize)
                .overlay(
                    Circle()
                        .stroke(Theme.Color.Shutter.strokeTop, lineWidth: 0.8)
                )
                .shadow(color: Theme.Color.background.opacity(0.4), radius: 3, x: 0, y: 1)
                .scaleEffect(configuration.isPressed ? 0.70 : 1.0)
                .animation(Theme.Physics.shutterTop, value: configuration.isPressed)
        }
        .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
        .contentShape(Circle())
        .onChange(of: configuration.isPressed) { _, isPressed in
            if isPressed {
                hapticGenerator.prepare()
                hapticGenerator.impactOccurred()
                Task { @MainActor in action() }
            }
        }
    }
}
