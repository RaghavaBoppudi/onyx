import SwiftUI

struct RootView: View {
    let settings: AppSettings
    let model: CameraModel

    var body: some View {
        Group {
            switch model.phase {
            case .denied:
                PermissionGateView(
                    message: CaptureError.cameraAccessDenied.localizedDescription,
                    showsSettingsLink: true
                )
            case .failed(let message):
                PermissionGateView(message: message, showsSettingsLink: false)
            default:
                ViewfinderScreen(settings: settings, model: model)
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBar(hidden: true)
    }
}

private struct PermissionGateView: View {
    @Environment(\.openURL) private var openURL

    let message: String
    let showsSettingsLink: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                showsSettingsLink ? "Camera Access Needed" : "Camera Unavailable",
                systemImage: "camera.metering.unknown"
            )
        } description: {
            Text(message)
        } actions: {
            if showsSettingsLink {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.onyxAccent)
            }
        }
    }
}
