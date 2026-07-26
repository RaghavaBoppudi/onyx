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
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.4))
                .frame(width: Metrics.baseSize, height: Metrics.baseSize)
                .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
                .animation(.spring(response: 0.40, dampingFraction: 0.6), value: configuration.isPressed)
            
            Circle()
                .fill(Theme.accent.opacity(0.7))
                .frame(width: Metrics.midSize, height: Metrics.midSize)
                .scaleEffect(configuration.isPressed ? 0.80 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
            
            Circle()
                .fill(Theme.accent)
                .frame(width: Metrics.topSize, height: Metrics.topSize)
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
