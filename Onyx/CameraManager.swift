import Foundation
import AVFoundation
import CoreImage
import CoreLocation
import Combine

protocol FrameReceiver: AnyObject, Sendable {
    nonisolated func receive(image: CIImage?)
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = CameraHardware.availableLenses(for: .back)
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isSwitchingLens = false
    
    nonisolated(unsafe) weak var frameReceiver: FrameReceiver?
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let videoQueue = DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue", qos: .userInitiated)
    
    private let lock = NSLock()
    private let locationProvider = LocationProvider()
    private nonisolated(unsafe) var _frameCount = 0

    override init() {
        super.init()
        self.currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        sessionQueue.async { [weak self] in self?.setupCamera() }
    }
    
    private func setupCamera() {
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
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = (device.position == .front) }
            }
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        applySettings(to: device)
        session.commitConfiguration()
        session.startRunning()
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        _frameCount += 1
        let count = _frameCount
        lock.unlock()
        
        guard count > 10, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        let finalImage = OnyxFilterPipeline.apply(to: rawImage)
        frameReceiver?.receive(image: finalImage)
    }
    
    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self, let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
            settings.photoQualityPrioritization = .speed
            settings.isAutoRedEyeReductionEnabled = false
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, photo.isRawPhoto, let rawData = photo.fileDataRepresentation() else { return }
        PhotoProcessor.processAndSave(photoData: rawData, location: locationProvider.currentLocation)
    }
    
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
            if self.session.canAddInput(newInput) { self.session.addInput(newInput); self.videoDeviceInput = newInput }
            
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = (newDevice.position == .front) }
            }
            
            self.applySettings(to: newDevice)
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.isSwitchingLens = false }
            }
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

    private func applySettings(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
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
        } catch {
            print("Failed to apply camera settings: \(error)")
        }
    }
}
