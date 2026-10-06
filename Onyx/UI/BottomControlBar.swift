import SwiftUI

struct BottomControlBar: View {
    let model: CameraModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                Spacer()
                CaptureThumbnail(model: model)
                Spacer()
                ShutterButton(model: model)
                Spacer()
                if model.isJournalist {
                    Color.clear.frame(width: 47, height: 47)
                } else {
                    CameraFlipButton(model: model)
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            ProfilePicker(model: model)
                .frame(maxWidth: 260)
        }
    }
}
