//  PhotoCaptureProcessor.swift
//  Bridges AVCapturePhotoCaptureDelegate into structured concurrency.
//  Returns raw bytes only — every pixel decision happens in ImageRenderer.

import AVFoundation
import ImageIO

struct RawCapture: @unchecked Sendable {
    let data: Data
    let isRAW: Bool
    let orientation: CGImagePropertyOrientation
}

final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let orientation: CGImagePropertyOrientation
    private let onShutterFire: @Sendable () -> Void
    private var continuation: CheckedContinuation<RawCapture, Error>?
    private var payload: RawCapture?

    init(
        orientation: CGImagePropertyOrientation,
        onShutterFire: @escaping @Sendable () -> Void
    ) {
        self.orientation = orientation
        self.onShutterFire = onShutterFire
    }

    func attach(_ continuation: CheckedContinuation<RawCapture, Error>) {
        self.continuation = continuation
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
            Log.capture.error("didFinishProcessingPhoto: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Log.capture.error("No file data representation")
            return
        }
        payload = RawCapture(data: data, isRAW: photo.isRawPhoto, orientation: orientation)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        defer { continuation = nil; payload = nil }

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
