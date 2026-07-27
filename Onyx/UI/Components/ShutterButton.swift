import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {}) {
            SwiftUI.Color.clear
        }
        .buttonStyle(ShutterGlassStyle(action: action))
    }
}

private struct ShutterGlassStyle: ButtonStyle {
    let action: () -> Void
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Base Glass Tier
            Circle()
                .fill(Theme.Color.glassBackground)
                .liquidGlass(shape: Circle(), isBordered: true)
                .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(Theme.Physics.shutterBase, value: configuration.isPressed)
            
            // Middle Accent Ring
            Circle()
                .stroke(Theme.Color.Shutter.gradient, lineWidth: 2.0)
                .frame(width: Theme.Layout.Shutter.midSize, height: Theme.Layout.Shutter.midSize)
                .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
                .animation(Theme.Physics.shutterMid, value: configuration.isPressed)
            
            // Inner Brand Core
            Circle()
                .fill(Theme.Color.Shutter.gradient)
                .frame(width: Theme.Layout.Shutter.topSize, height: Theme.Layout.Shutter.topSize)
                .scaleEffect(configuration.isPressed ? 0.75 : 1.0)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
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
