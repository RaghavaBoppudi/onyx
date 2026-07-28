import SwiftUI
import AVFoundation

struct BottomControlsView: View {
    @Binding var isFlashOn: Bool
    let cameraPosition: AVCaptureDevice.Position
    let iconOrientation: Angle
    let onCameraPositionToggle: () -> Void
    let onShutterPress: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    isFlashOn.toggle()
                }) {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: Theme.Typography.iconStandard, weight: .bold))
                        .foregroundColor(isFlashOn ? Theme.Color.background : Theme.Color.text)
                        .frame(width: Theme.Layout.controlWidth, height: Theme.Layout.controlHeight)
                        .background(
                            Capsule().fill(isFlashOn ? Theme.Color.accent : Theme.Color.glassBorderSubtle)
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
                        .font(.system(size: Theme.Typography.iconStandard, weight: .bold))
                        .foregroundColor(cameraPosition == .front ? Theme.Color.background : Theme.Color.text)
                        .frame(width: Theme.Layout.controlWidth, height: Theme.Layout.controlHeight)
                        .background(
                            Capsule().fill(cameraPosition == .front ? Theme.Color.accent : Theme.Color.glassBorderSubtle)
                        )
                        .rotationEffect(iconOrientation)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Layout.paddingStandard)
        .background(Theme.Color.background)
    }
}
