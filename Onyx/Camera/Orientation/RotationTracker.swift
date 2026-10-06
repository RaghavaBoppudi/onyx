import AVFoundation
import ImageIO
import Observation
import SwiftUI

@MainActor
@Observable
final class RotationTracker {

    private(set) var captureAngle: CGFloat = 90
    private(set) var previewAngle: CGFloat = 90

    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
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
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()

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

        let captureAngles = coordinator.values(of: \.videoRotationAngleForHorizonLevelCapture)
        let previewAngles = coordinator.values(of: \.videoRotationAngleForHorizonLevelPreview)

        observationTasks = [
            Task { [weak self] in
                for await angle in captureAngles { self?.captureAngle = angle }
            },
            Task { [weak self] in
                for await angle in previewAngles { self?.previewAngle = angle }
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
