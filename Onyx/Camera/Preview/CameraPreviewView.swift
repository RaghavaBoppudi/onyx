//  CameraPreviewView.swift
//  AVCaptureVideoPreviewLayer wrapped for SwiftUI.
//
//  The layer registers itself with RotationTracker on creation. The rotation
//  coordinator needs the layer to compute a correct preview angle — constructing it
//  with `previewLayer: nil` is what made the first build render sideways.

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let sessionBox: CaptureSessionBox
    let rotation: RotationTracker

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = sessionBox.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black

        let layer = view.previewLayer
        Task { @MainActor in rotation.register(previewLayer: layer) }
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        if view.previewLayer.session !== sessionBox.session {
            view.previewLayer.session = sessionBox.session
        }
        if let connection = view.previewLayer.connection {
            let angle = rotation.previewAngle
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
