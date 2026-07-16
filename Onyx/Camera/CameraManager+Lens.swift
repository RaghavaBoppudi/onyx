import Foundation
import AVFoundation

extension CameraManager {
    func selectLens(_ targetLens: Lens) {
        guard targetLens != currentLens, availableLenses.contains(targetLens) else { return }
        self.isSwitchingLens = true
        self.currentLens = targetLens
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let newDevice = AVCaptureDevice.default(targetLens.type, for: .video, position: targetLens.position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
                  
            self.session.beginConfiguration()
            if let currentInput = self.videoDeviceInput { self.session.removeInput(currentInput) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
            }
            self.configureVideoConnection(for: newDevice)
            self.applySettings(to: newDevice)
            self.session.commitConfiguration()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.isSwitchingLens = false }
        }
    }

    func toggleCameraPosition() {
        let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        let newLenses = CameraHardware.availableLenses(for: newPosition)
        guard let firstLens = newLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? newLenses.first else { return }
        self.cameraPosition = newPosition
        self.availableLenses = newLenses
        selectLens(firstLens)
    }
    
    func lockFocusAndExposure(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let sensorPoint = CGPoint(x: point.y, y: 1.0 - point.x)
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = sensorPoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = sensorPoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = false
                device.unlockForConfiguration()
            } catch {}
        }
    }
    
    @objc internal func subjectAreaDidChange(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }
}
