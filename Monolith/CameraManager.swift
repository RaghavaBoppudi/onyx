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
    
    // Auto state tracking
    @Published var isFocusAuto: Bool = true
    @Published var isISOAuto: Bool = true
    @Published var isShutterAuto: Bool = true
    
    var currentExposureBias: Float = -1.8
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private let processor = PhotoProcessor()
    private let locationProvider = LocationProvider()
    let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let videoQueue = DispatchQueue(label: "com.monolith.videoQueue", qos: .userInteractive)

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
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        applySettings(to: device, bias: currentExposureBias)
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let mono = CIFilter.colorControls()
        mono.inputImage = rawImage
        mono.saturation = 0.0
        
        let curve = CIFilter.toneCurve()
        curve.inputImage = mono.outputImage
        curve.point0 = CGPoint(x: 0.0, y: 0.02)
        curve.point1 = CGPoint(x: 0.25, y: 0.30)
        curve.point2 = CGPoint(x: 0.5, y: 0.55)
        curve.point3 = CGPoint(x: 0.75, y: 0.80)
        curve.point4 = CGPoint(x: 1.0, y: 0.98)
        
        if let finalImage = curve.outputImage {
            DispatchQueue.main.async {
                self.livePreviewImage = finalImage
            }
        }
    }
    
    func capturePhoto() {
        guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
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
        
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        
        applySettings(to: newDevice, bias: currentExposureBias)
        session.commitConfiguration()
        
        DispatchQueue.main.async {
            self.currentFocus = newDevice.lensPosition
            self.currentISO = newDevice.iso
            self.currentShutter = CMTimeGetSeconds(newDevice.exposureDuration)
            self.isFocusAuto = true
            self.isISOAuto = true
            self.isShutterAuto = true
        }
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
        } catch {}
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
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO
                let newISO = max(minISO, min(maxISO, device.iso + delta * ((maxISO - minISO) * 0.005)))
                device.setExposureModeCustom(duration: device.exposureDuration, iso: newISO, completionHandler: nil)
                DispatchQueue.main.async {
                    self.isISOAuto = false
                    self.isShutterAuto = false
                }
                
            case .shutter:
                let currentShutter = CMTimeGetSeconds(device.exposureDuration)
                let minShutter = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
                let maxShutter = 1.0
                let newShutter = max(minShutter, min(maxShutter, currentShutter + Double(delta) * 0.002))
                device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newShutter, preferredTimescale: 1000000), iso: device.iso, completionHandler: nil)
                DispatchQueue.main.async {
                    self.isShutterAuto = false
                    self.isISOAuto = false
                }
                
            default: break
            }
            
            let f = device.lensPosition
            let i = device.iso
            let s = CMTimeGetSeconds(device.exposureDuration)
            
            DispatchQueue.main.async {
                self.currentFocus = f
                self.currentISO = i
                self.currentShutter = s
            }
            
            device.unlockForConfiguration()
        } catch {}
    }
    
    func resetToAuto(control: ManualControl) {
        guard let device = videoDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            switch control {
            case .focus:
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                DispatchQueue.main.async { self.isFocusAuto = true }
            case .iso, .shutter:
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    let clampedBias = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, currentExposureBias))
                    device.setExposureTargetBias(clampedBias, completionHandler: nil)
                }
                DispatchQueue.main.async {
                    self.isISOAuto = true
                    self.isShutterAuto = true
                }
            default: break
            }
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
