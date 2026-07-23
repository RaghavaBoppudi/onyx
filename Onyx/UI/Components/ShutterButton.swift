import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
        // Provide an empty closure to prevent the default touch-up-inside behavior
        Button(action: {}) {
            Color.clear
        }
        .buttonStyle(ShutterButtonStyle(action: action))
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    let action: () -> Void
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    private enum Metrics {
        static let baseSize: CGFloat = 88
        static let midSize: CGFloat = 68
        static let topSize: CGFloat = 48
        
        static let baseScale: CGFloat = 0.88
        static let midScale: CGFloat = 0.82
        static let topScale: CGFloat = 0.70
    }
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Bottom Layer
            LayerCircle(gradient: [Color(red: 0.5, green: 0.1, blue: 0.0), Color(red: 0.6, green: 0.2, blue: 0.0)])
                .frame(width: Metrics.baseSize, height: Metrics.baseSize)
                .scaleEffect(configuration.isPressed ? Metrics.baseScale : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: configuration.isPressed)
            
            // Middle Layer
            LayerCircle(gradient: [Color(red: 0.8, green: 0.15, blue: 0.05), Color(red: 0.9, green: 0.45, blue: 0.0)])
                .frame(width: Metrics.midSize, height: Metrics.midSize)
                .scaleEffect(configuration.isPressed ? Metrics.midScale : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
            
            // Top Layer
            LayerCircle(gradient: [Color(red: 1.0, green: 0.2, blue: 0.13), Color(red: 1.0, green: 0.6, blue: 0.0)])
                .frame(width: Metrics.topSize, height: Metrics.topSize)
                .scaleEffect(configuration.isPressed ? Metrics.topScale : 1.0)
                .animation(.spring(response: 0.12, dampingFraction: 0.6), value: configuration.isPressed)
        }
        .frame(width: Metrics.baseSize, height: Metrics.baseSize)
        .contentShape(Circle())
        .onChange(of: configuration.isPressed) { _, isPressed in
            if isPressed {
                // Fire haptics and capture immediately on touch down
                hapticGenerator.prepare()
                hapticGenerator.impactOccurred()
                action()
            }
        }
    }
}

private struct LayerCircle: View {
    let gradient: [Color]
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: gradient),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }
}
