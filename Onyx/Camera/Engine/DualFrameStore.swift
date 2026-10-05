import AVFoundation
import os

nonisolated struct DualFrames: @unchecked Sendable {
    let rear: CVPixelBuffer
    let front: CVPixelBuffer
}

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

    func snapshot() -> DualFrames? {
        latest.withLockUnchecked { state in
            guard let rear = state.rear, let front = state.front else { return nil }
            return DualFrames(rear: rear, front: front)
        }
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
