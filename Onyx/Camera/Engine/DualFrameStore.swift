import AVFoundation
import os

/// Pixel buffers are immutable once copied out of the store, so sharing them across tasks is safe.
nonisolated struct DualFrames: @unchecked Sendable {
    let rear: CVPixelBuffer
    let front: CVPixelBuffer
}

/// `latest` is guarded by an unfair lock; the outputs are configured once and then only used by the session.
nonisolated final class DualFrameStore: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    let rearOutput = AVCaptureVideoDataOutput()
    let frontOutput = AVCaptureVideoDataOutput()

    private nonisolated struct Latest: @unchecked Sendable {
        var rear: CVPixelBuffer?
        var front: CVPixelBuffer?
    }

    private let latest = OSAllocatedUnfairLock(uncheckedState: Latest())
    private let queue = DispatchQueue(label: "com.onyx.camera.dual-frames", qos: .userInitiated)

    override init() {
        super.init()
        for output in [rearOutput, frontOutput] {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
        }
    }

    func copySnapshot() -> DualFrames? {
        let held = latest.withLockUnchecked { state -> DualFrames? in
            guard let rear = state.rear, let front = state.front else { return nil }
            return DualFrames(rear: rear, front: front)
        }

        guard let held,
              let rear = held.rear.deepCopy(),
              let front = held.front.deepCopy()
        else { return nil }

        return DualFrames(rear: rear, front: front)
    }

    func reset() {
        latest.withLockUnchecked { state in
            state = Latest()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        latest.withLockUnchecked { state in
            if output === rearOutput {
                state.rear = buffer
            } else if output === frontOutput {
                state.front = buffer
            }
        }
    }
}

nonisolated extension CVPixelBuffer {

    func deepCopy() -> CVPixelBuffer? {
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(self),
            CVPixelBufferGetHeight(self),
            CVPixelBufferGetPixelFormatType(self),
            attributes,
            &created
        )
        guard status == kCVReturnSuccess, let copy = created else { return nil }

        CVBufferPropagateAttachments(self, copy)

        guard CVPixelBufferLockBaseAddress(self, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        guard CVPixelBufferLockBaseAddress(copy, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(copy, []) }

        let planeCount = CVPixelBufferGetPlaneCount(self)
        if planeCount == 0 {
            copyRows(
                from: CVPixelBufferGetBaseAddress(self),
                sourceStride: CVPixelBufferGetBytesPerRow(self),
                to: CVPixelBufferGetBaseAddress(copy),
                destinationStride: CVPixelBufferGetBytesPerRow(copy),
                rows: CVPixelBufferGetHeight(self)
            )
        } else {
            for plane in 0..<planeCount {
                copyRows(
                    from: CVPixelBufferGetBaseAddressOfPlane(self, plane),
                    sourceStride: CVPixelBufferGetBytesPerRowOfPlane(self, plane),
                    to: CVPixelBufferGetBaseAddressOfPlane(copy, plane),
                    destinationStride: CVPixelBufferGetBytesPerRowOfPlane(copy, plane),
                    rows: CVPixelBufferGetHeightOfPlane(self, plane)
                )
            }
        }
        return copy
    }
}

nonisolated private func copyRows(
    from source: UnsafeRawPointer?,
    sourceStride: Int,
    to destination: UnsafeMutableRawPointer?,
    destinationStride: Int,
    rows: Int
) {
    guard let source, let destination else { return }
    let rowBytes = min(sourceStride, destinationStride)
    for row in 0..<rows {
        memcpy(destination + row * destinationStride, source + row * sourceStride, rowBytes)
    }
}
