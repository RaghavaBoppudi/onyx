import Foundation
import AVFoundation
import CoreImage
import CoreLocation
import os

struct WeakReceiverBox { weak var receiver: FrameReceiver? }

actor CameraEngine {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let captureDelegate = EngineCaptureDelegate()
    private let locationProvider = LocationProvider()
    
    var availableLenses: [Lens] = []
    var currentLens: Lens?
    
    private var deviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false

    init() {}

    func setFrameReceiver(_ receiver: FrameReceiver?) {
        captureDelegate.frameReceiver = receiver
    }
    
    func setOnCapture(_ callback: @escaping @Sendable () -> Void) {
        captureDelegate.onCapture = callback
    }
    
    func setOnQRCodeScanned(_ callback: @escaping @Sendable (String) -> Void) {
        captureDelegate.onQRCodeScanned = callback
    }
    
    func start() async -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return false }
        } else if authStatus != .authorized {
            return false
        }
        
        guard !isConfigured else {
            if !session.isRunning { session.startRunning() }
            return true
        }
        
        availableLenses = CameraHardware.availableLenses(for: .back)
        currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        configureInput()
        configureVideoOutput()
        configurePhotoOutput()
        configureMetadataOutput()
        
        session.commitConfiguration()
        session.startRunning()
        isConfigured = true
        
        return true
    }
    
    func stop() {
        if session.isRunning { session.stopRunning() }
    }
    
    private func configureInput() {
        guard let lens = currentLens,
              let device = AVCaptureDevice.default(lens.type, for: .video, position: lens.position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
              
        if session.canAddInput(input) {
            session.addInput(input)
            deviceInput = input
        }
        applySettings(to: device)
    }
    
    private func configureVideoOutput() {
        videoOutput.setSampleBufferDelegate(captureDelegate, queue: DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        guard let device = deviceInput?.device else { return }
        
        if let connection = videoOutput.connection(with: .video) {
            let portraitAngle: CGFloat = (device.position == .front) ? 0.0 : 90.0
            if connection.isVideoRotationAngleSupported(portraitAngle) {
                connection.videoRotationAngle = portraitAngle
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (device.position == .front)
            }
        }
        
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }
    
    private func configurePhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
    }
    
    private func configureMetadataOutput() {
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(captureDelegate, queue: DispatchQueue(label: "com.onyx.metadataQueue", qos: .userInitiated))
            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
            }
        }
    }
    
    func switchCameraPosition(to position: AVCaptureDevice.Position) -> Lens? {
        availableLenses = CameraHardware.availableLenses(for: position)
        let newLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        if let lens = newLens { selectLens(lens) }
        return newLens
    }
    
    func selectLens(_ lens: Lens) {
        currentLens = lens
        guard let newDevice = AVCaptureDevice.default(lens.type, for: .video, position: lens.position),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
              
        session.beginConfiguration()
        if let currentInput = deviceInput { session.removeInput(currentInput) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            deviceInput = newInput
        }
        
        if let connection = videoOutput.connection(with: .video) {
            let portraitAngle: CGFloat = (newDevice.position == .front) ? 0.0 : 90.0
            if connection.isVideoRotationAngleSupported(portraitAngle) {
                connection.videoRotationAngle = portraitAngle
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (newDevice.position == .front)
            }
        }
        
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: newDevice, previewLayer: nil)
        applySettings(to: newDevice)
        session.commitConfiguration()
    }
    
    private func applySettings(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, -0.5)), completionHandler: nil)
            device.isSubjectAreaChangeMonitoringEnabled = false
            
            if let bestRange = device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                device.activeVideoMaxFrameDuration = bestRange.minFrameDuration
                device.activeVideoMinFrameDuration = bestRange.minFrameDuration
            }
            device.unlockForConfiguration()
        } catch {}
    }
    
    func capturePhoto() {
        if let photoConnection = photoOutput.connection(with: .video),
           let coordinator = rotationCoordinator {
            let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            if photoConnection.isVideoRotationAngleSupported(captureAngle) {
                photoConnection.videoRotationAngle = captureAngle
            }
        }
        
        let settings: AVCapturePhotoSettings
        // Restored standard Bayer RAW capture to bypass ISP sharpening
        if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
        settings.photoQualityPrioritization = .speed
        settings.isAutoRedEyeReductionEnabled = false
        settings.flashMode = .off
        
        captureDelegate.currentLocation = locationProvider.currentLocation
        
        photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
    }
}

final class EngineCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    private let _frameReceiver = OSAllocatedUnfairLock(initialState: WeakReceiverBox(receiver: nil))
    private let _currentLocation = OSAllocatedUnfairLock(initialState: CLLocation?(nil))
    private let _onCapture = OSAllocatedUnfairLock(initialState: (@Sendable () -> Void)?(nil))
    private let _onQRCodeScanned = OSAllocatedUnfairLock(initialState: (@Sendable (String) -> Void)?(nil))
    
    var onCapture: (@Sendable () -> Void)? {
        get { _onCapture.withLock { $0 } }
        set { _onCapture.withLock { $0 = newValue } }
    }
    
    var onQRCodeScanned: (@Sendable (String) -> Void)? {
        get { _onQRCodeScanned.withLock { $0 } }
        set { _onQRCodeScanned.withLock { $0 = newValue } }
    }
    
    var frameReceiver: FrameReceiver? {
        get { _frameReceiver.withLock { $0.receiver } }
        set { _frameReceiver.withLock { $0.receiver = newValue } }
    }
    
    var currentLocation: CLLocation? {
        get { _currentLocation.withLock { $0 } }
        set { _currentLocation.withLock { $0 = newValue } }
    }
    
    let ciContext = MTLCreateSystemDefaultDevice().map {
        CIContext(mtlDevice: $0, options: [.cacheIntermediates: false, .priorityRequestLow: false])
    } ?? CIContext(options: [.cacheIntermediates: false])

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let finalImage = OnyxFilterPipeline.apply(to: rawImage)
            frameReceiver?.receive(image: finalImage)
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let qrObject = metadataObjects.first(where: { $0.type == .qr }) as? AVMetadataMachineReadableCodeObject,
              let stringValue = qrObject.stringValue else { return }
        
        onQRCodeScanned?(stringValue)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        onCapture?()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let photoData = photo.fileDataRepresentation() else { return }
        let context = self.ciContext
        let location = self.currentLocation
        let isRaw = photo.isRawPhoto
        
        Task { await PhotoProcessor.processAndSave(photoData: photoData, isRaw: isRaw, location: location, context: context) }
    }
}
