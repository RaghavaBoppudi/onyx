import Foundation
import AVFoundation
import CoreImage
import Combine

enum ManualControl { case none, focus, shutter, iso, timer }

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var livePreviewImage: CIImage?
    
    @Published var currentFocus: Float = 0.0
    @Published var currentISO: Float = 0.0
    @Published var currentShutter: Double = 0.0
    
    @Published var isFocusAuto: Bool = true
    @Published var isISOAuto: Bool = true
    @Published var isShutterAuto: Bool = true
    @Published var isSwitchingLens = false
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let processor = PhotoProcessor()
    private let locationProvider = LocationProvider()
    let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let videoQueue = DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive)

    private var frameCount = 0
    
    let standardISOs: [Float] = [50, 100, 200, 400, 800, 1600, 3200, 6400]
    let standardShutterSpeeds: [Double] = [
        1.0, 1.0/2.0, 1.0/4.0, 1.0/8.0, 1.0/15.0, 1.0/30.0,
        1.0/60.0, 1.0/125.0, 1.0/250.0, 1.0/500.0, 1.0/1000.0,
        1.0/2000.0, 1.0/4000.0, 1.0/8000.0
    ]

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
        
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        applySettings(to: device)
        session.commitConfiguration()
        
        DispatchQueue.main.async {
            self.currentFocus = device.lensPosition
            self.currentISO = device.iso
            self.currentShutter = CMTimeGetSeconds(device.exposureDuration)
            self.isFocusAuto = true
            self.isISOAuto = true
            self.isShutterAuto = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount > 10, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let baseMono = rawImage.applyingOnyxMonochrome() else { return }
        
        let finalPreviewImage = baseMono.applyingOnyxToneCurve() ?? baseMono
        DispatchQueue.main.async { self.livePreviewImage = finalPreviewImage }
    }
    
    func capturePhoto() {
        guard frameCount > 10, let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
        settings.photoQualityPrioritization = .speed
        settings.isAutoRedEyeReductionEnabled = false
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, photo.isRawPhoto, let rawData = photo.fileDataRepresentation() else { return }
        processor.processAndSave(photoData: rawData, location: locationProvider.currentLocation)
    }
    
    func selectLens(_ targetLens: Lens) {
        guard targetLens != currentLens, availableLenses.contains(targetLens) else { return }
        self.isSwitchingLens = true
        self.currentLens = targetLens
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let newDevice = AVCaptureDevice.default(targetLens.type, for: .video, position: targetLens.position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
                  
            self.session.beginConfiguration()
            if let currentInput = self.videoDeviceInput { self.session.removeInput(currentInput) }
            if self.session.canAddInput(newInput) { self.session.addInput(newInput); self.videoDeviceInput = newInput }
            if let connection = self.videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            
            self.applySettings(to: newDevice)
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.currentFocus = newDevice.lensPosition
                self.currentISO = newDevice.iso
                self.currentShutter = CMTimeGetSeconds(newDevice.exposureDuration)
                self.isFocusAuto = true; self.isISOAuto = true; self.isShutterAuto = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.isSwitchingLens = false }
            }
        }
    }

    func setFocusAndExposure(at point: CGPoint, isManualMode: Bool) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let sensorPoint = CGPoint(x: point.y, y: 1.0 - point.x)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = sensorPoint
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            }
            if !isManualMode {
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = sensorPoint
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
            }
            device.unlockForConfiguration()
        } catch {}
    }
    
    func lockFocusAndExposure(at point: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point; device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point; device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = false
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.isFocusAuto = false; self.isISOAuto = false; self.isShutterAuto = false }
        } catch { print("Failed to lock AE/AF: \(error)") }
    }

    func setFocus(_ newFocus: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let clampedFocus = max(0.0, min(1.0, newFocus))
            device.setFocusModeLocked(lensPosition: clampedFocus, completionHandler: nil)
            DispatchQueue.main.async { self.isFocusAuto = false; self.currentFocus = clampedFocus }
            device.unlockForConfiguration()
        } catch {}
    }
    
    func setISO(_ newISO: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let minISO = device.activeFormat.minISO
            let maxISO = device.activeFormat.maxISO
            let clampedISO = min(max(newISO, minISO), maxISO)
            
            device.setExposureModeCustom(duration: device.exposureDuration, iso: clampedISO, completionHandler: nil)
            DispatchQueue.main.async { self.isISOAuto = false; self.isShutterAuto = false; self.currentISO = clampedISO }
            device.unlockForConfiguration()
        } catch {}
    }
    
    func setShutter(_ newShutter: Double) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let minShutter = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
            let maxShutter = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
            let clampedShutter = min(max(newShutter, minShutter), maxShutter)
            let finalDuration = CMTimeMakeWithSeconds(clampedShutter, preferredTimescale: 1000000)
            
            device.setExposureModeCustom(duration: finalDuration, iso: device.iso, completionHandler: nil)
            DispatchQueue.main.async { self.isShutterAuto = false; self.isISOAuto = false; self.currentShutter = clampedShutter }
            device.unlockForConfiguration()
        } catch {}
    }
    
    func resetToAuto(control: ManualControl) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            switch control {
            case .focus:
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                DispatchQueue.main.async { self.isFocusAuto = true }
            case .iso, .shutter:
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    device.setExposureTargetBias(0.0, completionHandler: nil)
                }
                DispatchQueue.main.async { self.isISOAuto = true; self.isShutterAuto = true }
            default: break
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private func applySettings(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, -0.5 )), completionHandler: nil)
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
        } catch { print("Failed to apply camera settings: \(error)") }
    }
}
