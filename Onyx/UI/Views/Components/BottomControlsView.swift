import SwiftUI

struct BottomControlsView: View {
    @Binding var isFlashOn: Bool
    let iconOrientation: Angle
    let onCameraPositionToggle: () -> Void
    let onShutterPress: () -> Void
    
    private let buttonWidth: CGFloat = 64
    private let buttonHeight: CGFloat = 40
    
    var body: some View {
        HStack(spacing: 0) {
            
            HStack {
                Spacer()
                Button(action: {
                    isFlashOn.toggle()
                }) {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(isFlashOn ? .white : .black)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(
                            Capsule()
                                .fill(isFlashOn ? Theme.accent : Color.white)
                        )
                        .rotationEffect(iconOrientation)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            ShutterButton(action: onShutterPress)
                .layoutPriority(1)
            
            HStack {
                Spacer()
                Button(action: onCameraPositionToggle) {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                        .rotationEffect(iconOrientation)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .background(Color.black)
    }
}
