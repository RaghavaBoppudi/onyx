import AVFoundation
import ImageIO
import Observation
import SwiftUI

@Observable
final class RotationTracker {

    private(set) var captureAngle: CGFloat = 90
    private(set) var previewAngle: CGFloat = 90

    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var boundLens: Lens?

    var glyphRotation: Angle {
        .degrees(Double(captureAngle) - 90)
    }

    func register(previewLayer: AVCaptureVideoPreviewLayer) {
        guard self.previewLayer !== previewLayer else { return }
        self.previewLayer = previewLayer
        if let lens = boundLens { bind(to: lens) }
    }

    func bind(to lens: Lens) {
        boundLens = lens
        observations.removeAll()

        guard let device = lens.resolveDevice() else {
            coordinator = nil
            return
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        self.coordinator = coordinator

        captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        previewAngle = coordinator.videoRotationAngleForHorizonLevelPreview

        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
                _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor [weak self] in self?.captureAngle = angle }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) {
                _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor [weak self] in self?.previewAngle = angle }
            }
        ]
    }
}

nonisolated extension CGImagePropertyOrientation {
    init(rotationAngle angle: CGFloat) {
        let normalised = Int((angle.truncatingRemainder(dividingBy: 360) + 360)
                                .truncatingRemainder(dividingBy: 360).rounded())
        self = switch normalised {
        case 0: .up
        case 90: .right
        case 180: .down
        default: .left
        }
    }
}
