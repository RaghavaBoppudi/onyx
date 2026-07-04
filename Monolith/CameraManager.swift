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
    @Published var isDoubleExposureMode: Bool = false {
        didSet {
            firstShotData = nil
            firstShotPreview = nil
            guard let device = videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let targetBias: Float = isDoubleExposureMode ? -1.5 : 0.0
                device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, targetBias)), completionHandler: nil)
                device.unlockForConfiguration()
            } catch { print("Failed to set exposure bias: \(error)") }
            applySettings(to: device)
        }
    }
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let processor = PhotoProcessor()
    private let locationProvider = LocationProvider()
    let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let videoQueue = DispatchQueue(label: "com.monolith.videoQueue", qos: .userInteractive)

    private var firstShotData: Data?
    private var firstShotPreview: CIImage?
    private var lastVideoFrame: CIImage?
    private var frameCount = 0
    
    private var accumulatedISODelta: Float = 0
    private var accumulatedShutterDelta: Float = 0
    private let isoSteps: [Float] = [50, 100, 200, 400, 800, 1600, 3200]
    private let shutterSteps: [Double] = [1.0, 1.0/2.0, 1.0/4.0, 1.0/8.0, 1.0/15.0, 1.0/30.0, 1.0/60.0, 1.0/125.0, 1.0/250.0, 1.0/500.0, 1.0/1000.0, 1.0/2000.0]

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
        guard let baseMono = rawImage.applyingMonolithMonochrome() else { return }
        
        var finalPreviewImage: CIImage
        
        if let firstPreview = firstShotPreview {
            let blend = CIFilter.screenBlendMode()
            blend.inputImage = baseMono
            blend.backgroundImage = firstPreview
            let blended = blend.outputImage ?? baseMono
            finalPreviewImage = blended.applyingMonolithToneCurve() ?? blended
        } else {
            self.lastVideoFrame = baseMono
            finalPreviewImage = baseMono.applyingMonolithToneCurve() ?? baseMono
        }
        
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
        
        if isDoubleExposureMode {
            if firstShotData == nil {
                firstShotData = rawData
                firstShotPreview = lastVideoFrame
            } else {
                let first = firstShotData!
                firstShotData = nil
                firstShotPreview = nil
                processor.processAndSave(photoData: first, secondaryData: rawData, location: locationProvider.currentLocation)
            }
        } else {
            processor.processAndSave(photoData: rawData, secondaryData: nil, location: locationProvider.currentLocation)
        }
    }
    
    func selectLens(_ targetLens: Lens) {
        guard targetLens != currentLens, availableLenses.contains(targetLens) else { return }
        self.isSwitchingLens = true
        self.currentLens = targetLens
        self.firstShotData = nil
        self.firstShotPreview = nil
        
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

    func adjust(control: ManualControl, delta: Float) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            switch control {
            case .focus:
                let newFocus = max(0.0, min(1.0, device.lensPosition + delta * 0.005))
                device.setFocusModeLocked(lensPosition: newFocus, completionHandler: nil)
                DispatchQueue.main.async { self.isFocusAuto = false }
            case .iso:
                accumulatedISODelta += delta
                if abs(accumulatedISODelta) > 15 {
                    let direction = accumulatedISODelta > 0 ? 1 : -1
                    accumulatedISODelta = 0
                    var closestIdx = 0
                    for (i, val) in isoSteps.enumerated() { if abs(val - device.iso) < abs(isoSteps[closestIdx] - device.iso) { closestIdx = i } }
                    let nextIdx = max(0, min(isoSteps.count - 1, closestIdx + direction))
                    let newISO = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, isoSteps[nextIdx]))
                    device.setExposureModeCustom(duration: device.exposureDuration, iso: newISO, completionHandler: nil)
                    DispatchQueue.main.async { self.isISOAuto = false; self.isShutterAuto = false }
                }
            case .shutter:
                accumulatedShutterDelta += delta
                if abs(accumulatedShutterDelta) > 15 {
                    let direction = accumulatedShutterDelta > 0 ? 1 : -1
                    accumulatedShutterDelta = 0
                    let current = CMTimeGetSeconds(device.exposureDuration)
                    var closestIdx = 0
                    for (i, val) in shutterSteps.enumerated() { if abs(val - current) < abs(shutterSteps[closestIdx] - current) { closestIdx = i } }
                    let nextIdx = max(0, min(shutterSteps.count - 1, closestIdx + direction))
                    let newShutter = max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), min(1.0, shutterSteps[nextIdx]))
                    device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newShutter, preferredTimescale: 1000000), iso: device.iso, completionHandler: nil)
                    DispatchQueue.main.async { self.isShutterAuto = false; self.isISOAuto = false }
                }
            default: break
            }
            let f = device.lensPosition; let i = device.iso; let s = CMTimeGetSeconds(device.exposureDuration)
            DispatchQueue.main.async { self.currentFocus = f; self.currentISO = i; self.currentShutter = s }
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
            let targetBias: Float = isDoubleExposureMode ? -1.5 : 0.0
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, targetBias)), completionHandler: nil)
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
