import SwiftUI

struct BottomControlBar: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            CaptureThumbnail(model: model)
            Spacer()
            ShutterButton(model: model)
            Spacer()
            CameraFlipButton(model: model)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
