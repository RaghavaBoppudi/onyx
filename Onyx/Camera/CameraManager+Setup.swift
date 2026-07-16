import Foundation
import AVFoundation

extension CameraManager {
    internal func setupCamera() {
        session.automaticallyConfiguresApplicationAudioSession = false
        
        guard let currentLens = currentLens else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(currentLens.type, for: .video, position: currentLens.position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
            self.videoDeviceInput = input
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            configureVideoConnection(for: device)
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        applySettings(to: device)
        session.commitConfiguration()
        session.startRunning()
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil)
    }
    
    internal func configureVideoConnection(for device: AVCaptureDevice) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        let portraitAngle: CGFloat = (device.position == .front) ? 0.0 : 90.0
        
        if connection.isVideoRotationAngleSupported(portraitAngle) { connection.videoRotationAngle = portraitAngle }
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = (device.position == .front) }
        
        self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }
    
    internal func applySettings(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.isSubjectAreaChangeMonitoringEnabled = true
            
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, -0.5)), completionHandler: nil)
            
            if let bestRange = device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                device.activeVideoMaxFrameDuration = bestRange.minFrameDuration
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 5200.0, tint: 0.0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                gains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
                gains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
                gains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch { print("Failed to apply settings: \(error)") }
    }
}
