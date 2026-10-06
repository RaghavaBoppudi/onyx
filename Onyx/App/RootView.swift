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
    @Environment(\.theme) private var theme

    let message: String
    let showsSettingsLink: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: Symbols.noPermission)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.iconInactive)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if showsSettingsLink, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(Typography.caption)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }
}
