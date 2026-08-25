//  RootView.swift

import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme

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
        .themed(settings.appearance.resolved(against: systemScheme))
        .preferredColorScheme(settings.appearance.preferredColorScheme)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if model == nil { model = CameraModel(settings: settings) }
        }
    }
}
