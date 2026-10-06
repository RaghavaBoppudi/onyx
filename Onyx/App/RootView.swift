import SwiftUI

struct RootView: View {
    @State private var settings = AppSettings()
    @State private var model: CameraModel?

    var body: some View {
        Group {
            if let model {
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
            } else {
                Color.clear
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBar(hidden: true)
        .onAppear {
            if model == nil { model = CameraModel(settings: settings) }
        }
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
                .buttonStyle(.glass)
            }
        }
    }
}
