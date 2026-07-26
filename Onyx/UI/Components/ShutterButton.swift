import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
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
        static let baseSize: CGFloat = 104
        static let midSize: CGFloat = 80
        static let topSize: CGFloat = 56
    }
    
    // A single unified gradient that spans the entire component organically
    private var globalAssetGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.22, blue: 0.22), location: 0.0),
                .init(color: Color(red: 0.95, green: 0.42, blue: 0.08), location: 0.4),
                .init(color: Color(red: 0.45, green: 0.22, blue: 0.02), location: 0.75),
                .init(color: Color(red: 0.08, green: 0.05, blue: 0.03), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Base Tier (Outermost)
            Circle()
                .fill(globalAssetGradient)
                .frame(width: Metrics.baseSize, height: Metrics.baseSize)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.6), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.7), radius: 6, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
                .animation(.spring(response: 0.40, dampingFraction: 0.6), value: configuration.isPressed)
            
            // Middle Tier
            Circle()
                .fill(globalAssetGradient)
                .frame(width: Metrics.midSize, height: Metrics.midSize)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 1.0)
                )
                // Soft ambient occlusion shadow cast onto the layer below it
                .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
                .scaleEffect(configuration.isPressed ? 0.80 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
            
            // Top Tier (Innermost)
            Circle()
                .fill(globalAssetGradient)
                .frame(width: Metrics.topSize, height: Metrics.topSize)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.4), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                .scaleEffect(configuration.isPressed ? 0.70 : 1.0)
                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: configuration.isPressed)
        }
        .frame(width: Metrics.baseSize, height: Metrics.baseSize)
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
