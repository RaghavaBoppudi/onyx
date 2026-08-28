//  RotationTracker.swift
//  Main-actor owner of AVCaptureDevice.RotationCoordinator.
//
//  The preview layer must be handed to the coordinator. Constructing it with
//  `previewLayer: nil` — which the previous build did — leaves
//  `videoRotationAngleForHorizonLevelPreview` without the layer geometry it needs,
//  and the preview renders sideways. `CameraPreviewView` registers its layer here
//  as soon as it exists, and any lens already selected is rebound immediately.

import AVFoundation
import Observation
import QuartzCore

@MainActor
@Observable
final class RotationTracker {

    private(set) var captureAngle: CGFloat = 90
    private(set) var previewAngle: CGFloat = 90

    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var boundLens: Lens?

    /// Called by CameraPreviewView once the layer exists.
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
            // KVO fires on whatever thread AVFoundation picks, so the outer
            // closure here isn't provably tied to any actor. The fix isn't a
            // capture-list modifier — nonisolated(unsafe) is only valid on a
            // property declaration, not inside [...], and using it here doesn't
            // compile. Instead, `weak self` moves onto the *inner*
            // `Task { @MainActor in ... }` closure: the outer closure's own body
            // never references `self` directly, only inside that nested closure,
            // so it captures nothing that needs a Sendable guarantee. The inner
            // closure's explicit `@MainActor` pin is a real, compiler-trusted
            // isolation guarantee, so capturing `self` there is fully legitimate.
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

    var glyphRotationDegrees: Double {
        OrientationResolver.glyphRotationDegrees(forRotationAngle: previewAngle)
    }
}
