import SwiftUI

struct ShutterButton: View {
    let action: () -> Void
    @State private var isPressed: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: isPressed ? 80 : 88, height: isPressed ? 80 : 88)
            Circle()
                .fill(Theme.accent)
                .frame(width: 72, height: 72)
        }
        .frame(width: 88, height: 88)
        .animation(.spring(response: 0.15, dampingFraction: 0.65), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in
                    action()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
                }
        )
    }
}
