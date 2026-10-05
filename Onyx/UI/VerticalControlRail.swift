import SwiftUI

struct VerticalControlRail: View {
    let model: CameraModel
    let settings: AppSettings
    let onModesAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let centerY = proxy.size.height / 2
            let shutterRadius = Metrics.Shutter.outerDiameter / 2
            let spacing = Metrics.Chrome.railItemSpacing
            let topHeight = Metrics.Chrome.statusGroupHeight
            let bottomHeight = Metrics.Chrome.captureGroupHeight

            let halfSpan = shutterRadius + spacing + max(topHeight, bottomHeight)
            let available = max(centerY - Metrics.Chrome.railVerticalInset, 1)
            let scale = halfSpan > available ? available / halfSpan : 1

            ZStack {
                StatusControls(
                    axis: .vertical,
                    settings: settings,
                    model: model
                )
                .scaleEffect(scale)
                .position(x: centerX, y: centerY - (shutterRadius + spacing + topHeight / 2) * scale)

                ShutterButton(model: model)
                    .scaleEffect(scale)
                    .position(x: centerX, y: centerY)

                VStack(spacing: spacing) {
                    CameraFlipButton(model: model)
                    CaptureThumbnail(model: model)
                    ModeButton(model: model, action: onModesAction)
                }
                .scaleEffect(scale)
                .position(x: centerX, y: centerY + (shutterRadius + spacing + bottomHeight / 2) * scale)
            }
        }
    }
}
