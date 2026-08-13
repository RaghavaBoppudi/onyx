import SwiftUI

struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void
    
    var body: some View {
        ZStack {
            // Outer Ring - Structurally isolated from the button's internal state
            Circle()
                .stroke(Theme.Color.Shutter.ring, lineWidth: Theme.Layout.Shutter.ringWidth)
                .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
            
            // Inner Core - The actual interactive target
            Button(action: {
                guard !isCapturing else { return }
                action()
            }) {
                Color.clear
            }
            .buttonStyle(ShutterCoreStyle(isCapturing: isCapturing))
            .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
        }
    }
}

private struct ShutterCoreStyle: ButtonStyle {
    let isCapturing: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(configuration.isPressed ? Theme.Color.Shutter.pressed : Theme.Color.Shutter.core)
            .frame(width: Theme.Layout.Shutter.coreSize, height: Theme.Layout.Shutter.coreSize)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(isCapturing ? 0.5 : 1.0)
            .animation(Theme.Physics.shutterPress, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.1), value: isCapturing)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticManager.shared.playHeavy()
                }
            }
    }
}
