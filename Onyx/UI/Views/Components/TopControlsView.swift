import SwiftUI

struct PipelineToggleView: View {
    @Binding var useZeroProcessing: Bool
    let iconOrientation: Angle
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            useZeroProcessing.toggle()
            action()
        }) {
            Capsule()
                .fill(Color.white)
                .frame(width: 64, height: 32)
                .overlay(
                    Text(useZeroProcessing ? "ZERO" : "SMART")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .rotationEffect(iconOrientation)
                )
        }
    }
}

struct CameraPositionToggleView: View {
    let iconOrientation: Angle
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(Color.white)
                .frame(width: 64, height: 32)
                .overlay(
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .rotationEffect(iconOrientation)
                )
        }
    }
}

struct TopControlsView: View {
    @Binding var useZeroProcessing: Bool
    let iconOrientation: Angle
    let onPipelineToggle: () -> Void
    let onCameraPositionToggle: () -> Void
    
    var body: some View {
        HStack {
            PipelineToggleView(
                useZeroProcessing: $useZeroProcessing,
                iconOrientation: iconOrientation,
                action: onPipelineToggle
            )
            
            Spacer()
            
            CameraPositionToggleView(
                iconOrientation: iconOrientation,
                action: onCameraPositionToggle
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(Color.black)
    }
}
