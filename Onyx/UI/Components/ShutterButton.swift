import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    let isCapturing: Bool
    
    @GestureState private var isPressed: Bool = false
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            // Outer ring remains completely static
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: 88, height: 88)
            
            // Inner core with reduced travel distance
            Circle()
                .fill(Theme.accent)
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
