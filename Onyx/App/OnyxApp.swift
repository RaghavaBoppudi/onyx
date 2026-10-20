import SwiftUI

@main
struct OnyxApp: App {
    @State private var settings: AppSettings
    @State private var model: CameraModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: CameraModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate {
                RootView(settings: settings, model: model)
            }
            .preferredColorScheme(.dark)
            .persistentSystemOverlays(.hidden)
            .statusBar(hidden: true)
        }
    }
}
