import SwiftUI

struct ShutterButtonStyle: ButtonStyle {
    var isCapturing: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: configuration.isPressed || isCapturing ? 80 : 88, height: configuration.isPressed || isCapturing ? 80 : 88)
                .opacity(isCapturing ? 0.5 : 1.0)
            Circle()
                .fill(Theme.accent)
                .frame(width: 72, height: 72)
                .opacity(isCapturing ? 0.5 : 1.0)
        }
        .frame(width: 88, height: 88)
        .animation(.spring(response: 0.15, dampingFraction: 0.65), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.1), value: isCapturing)
    }
}

struct ShutterButton: View {
    let action: () -> Void
    let isCapturing: Bool
    
    var body: some View {
        Button(action: action) {
            Color.clear
        }
        .buttonStyle(ShutterButtonStyle(isCapturing: isCapturing))
        .disabled(isCapturing)
    }
}
