import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Color.clear
        }
        .buttonStyle(ShutterFlatStyle())
    }
}

private struct ShutterFlatStyle: ButtonStyle {
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Outer Ring
            Circle()
                .stroke(configuration.isPressed ? Theme.Color.Shutter.pressed : Theme.Color.Shutter.ring, lineWidth: Theme.Layout.Shutter.ringWidth)
                .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
            
            // Inner Core
            Circle()
                .fill(configuration.isPressed ? Theme.Color.Shutter.pressed : Theme.Color.Shutter.core)
                .frame(width: Theme.Layout.Shutter.coreSize, height: Theme.Layout.Shutter.coreSize)
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
        }
        .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
        .contentShape(Circle())
        .animation(Theme.Physics.shutterPress, value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { _, isPressed in
            if isPressed {
                hapticGenerator.prepare()
                hapticGenerator.impactOccurred()
            }
        }
    }
}
