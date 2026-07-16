import Foundation
import AVFoundation
import CoreImage
import os

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            let count = _frameCount.withLock { state in
                state += 1
                return state
            }
            guard count > 10, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let finalImage = OnyxFilterPipeline.apply(to: rawImage)
            frameReceiver?.receive(image: finalImage)
        }
    }
    
    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let photoConnection = self.photoOutput.connection(with: .video),
               let coordinator = self.rotationCoordinator {
                let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                if photoConnection.isVideoRotationAngleSupported(captureAngle) {
                    photoConnection.videoRotationAngle = captureAngle
                }
            }
            
            guard let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
            settings.photoQualityPrioritization = .speed
            settings.isAutoRedEyeReductionEnabled = false
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, photo.isRawPhoto, let rawData = photo.fileDataRepresentation() else { return }
        let context = self.ciContext
        Task { @MainActor in
            let location = self.locationProvider.currentLocation
            PhotoProcessor.processAndSave(photoData: rawData, location: location, context: context)
        }
    }
}
