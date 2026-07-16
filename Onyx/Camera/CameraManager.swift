import Foundation
import AVFoundation
import CoreImage
import CoreLocation
import Combine
import os

final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = CameraHardware.availableLenses(for: .back)
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isSwitchingLens = false
    
    nonisolated(unsafe) weak var frameReceiver: FrameReceiver?
    
    let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    // Internal state accessible to extensions within this file
    internal var videoDeviceInput: AVCaptureDeviceInput?
    internal let videoOutput = AVCaptureVideoDataOutput()
    internal let photoOutput = AVCapturePhotoOutput()
    
    internal let videoQueue = DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive)
    internal let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue", qos: .userInitiated)
    internal let locationProvider = LocationProvider()
    internal let _frameCount = OSAllocatedUnfairLock(initialState: 0)
    internal var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    override init() {
        super.init()
        self.currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        sessionQueue.async { [weak self] in self?.setupCamera() }
    }
}

// MARK: - Setup & Configuration
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: nil)
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

// MARK: - Lens Management
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
}

// MARK: - Focus & Exposure
extension CameraManager {
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

// MARK: - Capture Delegates
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let count = _frameCount.withLock { state in
            state += 1
            return state
        }
        guard count > 10, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        let finalImage = OnyxFilterPipeline.apply(to: rawImage)
        frameReceiver?.receive(image: finalImage)
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
