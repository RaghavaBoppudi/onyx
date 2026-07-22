import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    let isCapturing: Bool
    
    @GestureState private var isPressed: Bool = false
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            // Glass outer ring
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            }
            
            // Inner Core
            ZStack {
                // Solid Base
                Circle()
                    .fill(Color(white: 0.15))
                
                // Liquid Glass Specular Highlight
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.35), Color.clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 72, height: 72)
            .scaleEffect(isPressed || isCapturing ? 0.93 : 1.0)
            .opacity(isCapturing ? 0.5 : 1.0)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
                .onChanged { _ in
                    hapticGenerator.prepare()
                    hapticGenerator.impactOccurred()
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                action()
            }
        )
        .disabled(isCapturing)
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .animation(.easeInOut(duration: 0.08), value: isCapturing)
    }
}
