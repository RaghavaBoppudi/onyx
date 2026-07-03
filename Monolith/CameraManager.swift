import Foundation
import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    
    var currentExposureBias: Float = -1.8
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let processor = PhotoProcessor()
    private let locationProvider = LocationProvider()

    override init() {
        super.init()
        self.availableLenses = CameraHardware.availableLenses()
        self.currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        setupCamera()
    }
    
    private func setupCamera() {
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
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        applySettings(to: device, bias: currentExposureBias)
        
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    func capturePhoto() {
        guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            print("RAW capture not supported.")
            return
        }
        
        let processedFormat = [AVVideoCodecKey: AVVideoCodecType.hevc]
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
        
        settings.photoQualityPrioritization = .speed
        settings.isAutoRedEyeReductionEnabled = false
        settings.flashMode = .off
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, photo.isRawPhoto, let rawData = photo.fileDataRepresentation() else { return }
        let location = locationProvider.currentLocation
        processor.processAndSave(photoData: rawData, location: location)
    }
    
    func cycleLens() {
        guard let currentLens = currentLens, let currentIndex = availableLenses.firstIndex(of: currentLens) else { return }
        let nextIndex = (currentIndex + 1) % availableLenses.count
        self.currentLens = availableLenses[nextIndex]
        
        guard let newDevice = AVCaptureDevice.default(self.currentLens!.type, for: .video, position: self.currentLens!.position),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
              
        session.beginConfiguration()
        if let currentInput = videoDeviceInput { session.removeInput(currentInput) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            self.videoDeviceInput = newInput
        }
        
        applySettings(to: newDevice, bias: currentExposureBias)
        session.commitConfiguration()
    }
    
    func setFocusAndExposure(at point: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            let sensorPoint = CGPoint(x: point.y, y: 1.0 - point.x)
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = sensorPoint
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = sensorPoint
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Configuration lock failed: \(error)")
        }
    }
    
    func setExposureBias(_ bias: Float) {
        guard let device = videoDeviceInput?.device else { return }
        currentExposureBias = bias
        
        do {
            try device.lockForConfiguration()
            let clampedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
    }
    
    private func applySettings(to device: AVCaptureDevice, bias: Float) {
        do {
            try device.lockForConfiguration()
            
            let clampedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            
            if device.isWhiteBalanceModeSupported(.locked) {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 5200.0, tint: 0.0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                
                gains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
                gains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
                gains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
                
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
            
            device.unlockForConfiguration()
        } catch {}
    }
}
