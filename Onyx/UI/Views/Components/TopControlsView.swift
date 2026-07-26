import SwiftUI

struct TopControlsView: View {
    @Binding var isSettingsOpen: Bool
    let iconOrientation: Angle
    
    // Strict metrics to prevent arbitrary sizing
    private let buttonWidth: CGFloat = 64
    private let buttonHeight: CGFloat = 40
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isSettingsOpen.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isSettingsOpen ? .white : .black)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(
                        Capsule()
                            .fill(isSettingsOpen ? Theme.accent : Color.white)
                    )
                    .rotationEffect(iconOrientation)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black)
    }
}
