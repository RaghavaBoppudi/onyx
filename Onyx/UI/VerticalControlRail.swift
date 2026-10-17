import SwiftUI

struct VerticalControlRail: View {
    @Bindable var settings: AppSettings
    let model: CameraModel
    let onShowModes: () -> Void

    private let contentHeight: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, max(proxy.size.height - 80, 1) / contentHeight)

            content
                .frame(width: proxy.size.width, height: contentHeight)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var content: some View {
        VStack(spacing: 22) {
            StatusControls(
                settings: settings,
                axis: .vertical,
                model: model,
                onShowModes: onShowModes
            )

            Spacer(minLength: 0)

            ShutterButton(model: model)

            Spacer(minLength: 0)

            VStack(spacing: 22) {
                CameraFlipButton(model: model)
                CaptureThumbnail(model: model)
            }
        }
    }
}
