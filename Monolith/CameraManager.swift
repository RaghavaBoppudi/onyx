import Foundation
import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var isMonochrome = true
    
    // Default baseline EV. Underexposes to protect highlights and preserve natural shadows.
    var currentExposureBias: Float = -1.5
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let processor = PhotoProcessor()

    override init() {
        super.init()
        self.availableLenses = HardwareScanner.availableLenses()
        self.currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        setupCamera()
    }
    
    // Initializes the capture pipeline, strictly enforcing RAW photo output.
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
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        applyExposureBias(device: device, bias: currentExposureBias)
        
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    // Fires the shutter. Disables Apple's native red-eye and computational flash logic.
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
    
    // Intercepts the RAW sensor data and hands it off to the custom processing pipeline.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, photo.isRawPhoto, let rawData = photo.fileDataRepresentation() else { return }
        processor.processAndSave(photoData: rawData, isMonochrome: isMonochrome)
    }
    
    // Hot-swaps the physical camera input while keeping the session alive.
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
        
        applyExposureBias(device: newDevice, bias: currentExposureBias)
        session.commitConfiguration()
    }
    
    // Translates SwiftUI tap coordinates into the hardware sensor's coordinate space.
    func setFocusAndExposure(at point: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Map portrait UI coordinates (x, y) to landscape hardware coordinates (y, 1-x).
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
    
    // Updates the global EV target variable and immediately applies it to the hardware.
    func setExposureBias(_ bias: Float) {
        guard let device = videoDeviceInput?.device else { return }
        currentExposureBias = bias
        applyExposureBias(device: device, bias: bias)
    }
    
    // Hardware-level lock to physically alter the sensor's exposure target.
    private func applyExposureBias(device: AVCaptureDevice, bias: Float) {
        do {
            try device.lockForConfiguration()
            let clampedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {}
    }
}
