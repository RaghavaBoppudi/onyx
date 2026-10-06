import AVFoundation
import CoreLocation
import ImageIO
import Synchronization
import os

nonisolated struct RawCapture: Sendable {
    let data: Data
    let isRAW: Bool
    let orientation: CGImagePropertyOrientation
}

nonisolated struct CaptureRequest: Sendable {
    let id: UUID
    let mode: CaptureMode
    let position: AVCaptureDevice.Position
    let rotationAngle: CGFloat
    let isPortrait: Bool
    let flashMode: AVCaptureDevice.FlashMode
    let location: CLLocation?

    var orientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(rotationAngle: rotationAngle)
    }
}

nonisolated final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, Sendable {

    private nonisolated struct State {
        var continuation: CheckedContinuation<RawCapture, Error>?
        var payload: RawCapture?
    }

    private let orientation: CGImagePropertyOrientation
    private let onShutterFire: @Sendable () -> Void
    private let state = Mutex(State())

    init(
        orientation: CGImagePropertyOrientation,
        onShutterFire: @escaping @Sendable () -> Void
    ) {
        self.orientation = orientation
        self.onShutterFire = onShutterFire
    }

    func attach(_ continuation: CheckedContinuation<RawCapture, Error>) {
        state.withLock { $0.continuation = continuation }
    }

    func abort(with error: CaptureError) {
        let continuation = state.withLock { state -> CheckedContinuation<RawCapture, Error>? in
            let taken = state.continuation
            state.continuation = nil
            state.payload = nil
            return taken
        }
        continuation?.resume(throwing: error)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        onShutterFire()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Log.capture.error("didFinishProcessingPhoto: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Log.capture.error("No file data representation")
            return
        }
        let capture = RawCapture(data: data, isRAW: photo.isRawPhoto, orientation: orientation)
        state.withLock { $0.payload = capture }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        let (continuation, payload) = state.withLock {
            state -> (CheckedContinuation<RawCapture, Error>?, RawCapture?) in
            let taken = (state.continuation, state.payload)
            state.continuation = nil
            state.payload = nil
            return taken
        }

        if let error {
            continuation?.resume(throwing: CaptureError.captureFailed(error.localizedDescription))
            return
        }
        guard let payload else {
            continuation?.resume(throwing: CaptureError.noImageData)
            return
        }
        continuation?.resume(returning: payload)
    }
}
