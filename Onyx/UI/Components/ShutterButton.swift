import SwiftUI

struct ShutterButton: View {
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Color.Shutter.ring, lineWidth: Theme.Layout.Shutter.ringWidth)
                .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
            
            Button(action: {
                guard !isProcessing else { return }
                action()
            }) {
                Color.clear
            }
            .buttonStyle(ShutterCoreStyle())
            .frame(width: Theme.Layout.Shutter.baseSize, height: Theme.Layout.Shutter.baseSize)
        }
    }
}

private struct ShutterCoreStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(configuration.isPressed ? Theme.Color.Shutter.pressed : Theme.Color.Shutter.core)
            .frame(width: Theme.Layout.Shutter.coreSize, height: Theme.Layout.Shutter.coreSize)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.Physics.shutterPress, value: configuration.isPressed)
    }
}
