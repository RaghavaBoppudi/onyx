import SwiftUI

struct RootView: View {
    let settings: AppSettings
    let model: CameraModel

    var body: some View {
        if case .failed(let message) = model.phase {
            ContentUnavailableView(
                "Camera Unavailable",
                systemImage: "camera.metering.unknown",
                description: Text(message)
            )
        } else {
            ViewfinderScreen(settings: settings, model: model)
        }
    }
}
