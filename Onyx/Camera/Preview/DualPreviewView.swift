import AVFoundation
import SwiftUI

struct DualPreviewView: View {
    let box: DualSessionBox
    let rotation: RotationTracker
    let secondaryRotation: RotationTracker
    let style: DualLayoutStyle

    var body: some View {
        GeometryReader { proxy in
            let geometry = DualLayoutGeometry(size: proxy.size, style: style)

            ZStack(alignment: .topLeading) {
                PreviewLayerView(layer: box.rearPreviewLayer, rotation: rotation)
                    .frame(width: geometry.rear.width, height: geometry.rear.height)
                    .offset(x: geometry.rear.minX, y: geometry.rear.minY)

                PreviewLayerView(layer: box.frontPreviewLayer, rotation: secondaryRotation)
                    .frame(width: geometry.front.width, height: geometry.front.height)
                    .clipShape(.rect(cornerRadius: geometry.frontCornerRadius))
                    .offset(x: geometry.front.minX, y: geometry.front.minY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

private struct PreviewLayerView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer
    let rotation: RotationTracker

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView(previewLayer: layer)
        let previewLayer = layer
        Task { @MainActor in rotation.register(previewLayer: previewLayer) }
        return view
    }

    func updateUIView(_ view: LayerHostView, context: Context) {
        let angle = rotation.previewAngle
        guard layer.session?.isRunning == true,
              let connection = layer.connection,
              connection.isVideoRotationAngleSupported(angle)
        else { return }

        connection.videoRotationAngle = angle
    }

    final class LayerHostView: UIView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
