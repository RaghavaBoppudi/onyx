@preconcurrency import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreLocation
import os
import Photos

struct WeakReceiverBox: Sendable { weak var receiver: FrameReceiver? }

actor CameraEngine {
    private var session: AVCaptureSession!
    private let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue")
    
    private lazy var videoOutput = AVCaptureVideoDataOutput()
    private lazy var photoOutput = AVCapturePhotoOutput()
    private lazy var metadataOutput = AVCaptureMetadataOutput()
    
    private let captureDelegate = EngineCaptureDelegate()
    private let locationProvider = LocationProvider()
    
    var availableLenses: [Lens] = []
    var currentLens: Lens?
    var currentMode: ProcessingMode = .zero
    
    private var deviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false
    private var notificationTask: Task<Void, Never>?
    private var focusObservation: NSKeyValueObservation?

    func setFrameReceiver(_ receiver: FrameReceiver?) {
        captureDelegate.frameReceiver = receiver
    }
    
    func setOnCapture(_ callback: @escaping @Sendable () -> Void) {
        captureDelegate.onCapture = callback
    }
    
    func setOnCaptureComplete(_ callback: @escaping @Sendable () -> Void) {
        captureDelegate.onCaptureComplete = callback
    }
    
    func setOnQRCodeScanned(_ callback: @escaping @Sendable (String) -> Void) {
        captureDelegate.onQRCodeScanned = callback
    }
    
    func setOnFocusLocked(_ callback: @escaping @Sendable () -> Void) {
        captureDelegate.onFocusLocked = callback
    }
    
    func setOnStorageError(_ callback: @escaping @Sendable () -> Void) {
        captureDelegate.onStorageError = callback
    }
    
    func setProcessingPipeline(mode: ProcessingMode) {
        self.currentMode = mode
        captureDelegate.processingMode = mode
    }
    
    func setFocus(point: CGPoint) {
        guard let device = deviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            if device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for focus update.")
        }
    }
    
    private func resetFocusToContinuous() {
        guard let device = deviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            if device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for continuous focus reset.")
        }
    }
    
    func start() async -> Bool {
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuth == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        } else if cameraAuth != .authorized {
            return false
        }
        
        var photoAuth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoAuth == .notDetermined {
            photoAuth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard photoAuth == .authorized || photoAuth == .limited else {
            return false
        }
        
        if session == nil {
            session = AVCaptureSession()
            session.automaticallyConfiguresApplicationAudioSession = false
        }
        
        guard !isConfigured else {
            sessionQueue.async { [weak session] in
                if let s = session, !s.isRunning { s.startRunning() }
            }
            return true
        }
        
        availableLenses = CameraHardware.availableLenses(for: .back)
        currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        captureDelegate.activeDeviceType = currentLens?.type ?? .builtInWideAngleCamera
        
        let success: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                
                self.configureInput()
                self.configureVideoOutput()
                self.configurePhotoOutput()
                self.configureMetadataOutput()
                
                self.session.commitConfiguration()
                
                if let device = self.deviceInput?.device {
                    self.observeFocus(for: device)
                }
                
                self.session.startRunning()
                continuation.resume(returning: true)
            }
        }
        
        guard success else { return false }
        
        notificationTask?.cancel()
        notificationTask = Task {
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification) {
                resetFocusToContinuous()
            }
        }
        
        isConfigured = true
        return true
    }
    
    func stop() {
        notificationTask?.cancel()
        notificationTask = nil
        focusObservation?.invalidate()
        focusObservation = nil
        sessionQueue.async { [weak session] in
            if let s = session, s.isRunning { s.stopRunning() }
        }
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
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        
        guard let device = deviceInput?.device else { return }
        if let connection = videoOutput.connection(with: .video) {
            let portraitAngle: CGFloat = (device.position == .front) ? 0.0 : 90.0
            if connection.isVideoRotationAngleSupported(portraitAngle) { connection.videoRotationAngle = portraitAngle }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = (device.position == .front) }
        }
        
        Task {
            let coordinator = await MainActor.run { AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil) }
            self.rotationCoordinator = coordinator
        }
    }
    
    private func configurePhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if #available(iOS 17.0, *) {
                photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported
            }
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
        let newLens = availableLenses.first(where: { $0.label == "1x" }) ?? availableLenses.first
            
        if let lens = newLens { selectLens(lens) }
        return newLens
    }
    
    func selectLens(_ lens: Lens) {
        currentLens = lens
        captureDelegate.activeDeviceType = lens.type
        
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
            if connection.isVideoRotationAngleSupported(portraitAngle) { connection.videoRotationAngle = portraitAngle }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = (newDevice.position == .front) }
        }
        
        applySettings(to: newDevice)
        session.commitConfiguration()
        
        Task {
            let coordinator = await MainActor.run { AVCaptureDevice.RotationCoordinator(device: newDevice, previewLayer: nil) }
            self.rotationCoordinator = coordinator
        }
        
        observeFocus(for: newDevice)
    }
    
    private func observeFocus(for device: AVCaptureDevice) {
        focusObservation?.invalidate()
        focusObservation = device.observe(\.isAdjustingFocus, options: [.old, .new]) { [weak self] device, change in
            guard let old = change.oldValue, let new = change.newValue, old == true, new == false else { return }
            Task { [weak self] in await self?.captureDelegate.onFocusLocked?() }
        }
    }
    
    private func applySettings(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.setExposureTargetBias(-0.5, completionHandler: nil)
            
            if device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for settings application.")
        }
    }
    
    func capturePhoto(flashEnabled: Bool) {
        if let photoConnection = photoOutput.connection(with: .video), let coordinator = rotationCoordinator {
            let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            if photoConnection.isVideoRotationAngleSupported(captureAngle) { photoConnection.videoRotationAngle = captureAngle }
        }
        
        let settings: AVCapturePhotoSettings
        if let bayerFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: bayerFormat)
        } else {
            // Fallback for Front Cameras and older Ultra-Wide lenses that physically lack RAW capabilities
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        
        settings.isAutoRedEyeReductionEnabled = false
        
        let requestedFlashMode: AVCaptureDevice.FlashMode = flashEnabled ? .on : .off
        if photoOutput.supportedFlashModes.contains(requestedFlashMode) {
            settings.flashMode = requestedFlashMode
        } else {
            settings.flashMode = .off
        }
        
        if #available(iOS 16.0, *) {
            settings.photoQualityPrioritization = .speed
        }
        
        captureDelegate.currentLocation = locationProvider.currentLocation
        captureDelegate.processingMode = currentMode
        photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
    }
}

final class EngineCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    private let _frameReceiver = OSAllocatedUnfairLock(initialState: WeakReceiverBox(receiver: nil))
    private let _currentLocation = OSAllocatedUnfairLock(initialState: CLLocation?(nil))
    private let _onCapture = OSAllocatedUnfairLock(initialState: (@Sendable () -> Void)?(nil))
    private let _onCaptureComplete = OSAllocatedUnfairLock(initialState: (@Sendable () -> Void)?(nil))
    private let _onQRCodeScanned = OSAllocatedUnfairLock(initialState: (@Sendable (String) -> Void)?(nil))
    private let _onFocusLocked = OSAllocatedUnfairLock(initialState: (@Sendable () -> Void)?(nil))
    private let _onStorageError = OSAllocatedUnfairLock(initialState: (@Sendable () -> Void)?(nil))
    private let _processingMode = OSAllocatedUnfairLock(initialState: ProcessingMode.zero)
    private let _activeDeviceType = OSAllocatedUnfairLock(initialState: AVCaptureDevice.DeviceType.builtInWideAngleCamera)
    
    private let _lastScannedQR = OSAllocatedUnfairLock(initialState: (value: "", timestamp: Date.distantPast))
    
    private let filterPipeline = OnyxFilterPipeline()
    
    nonisolated var onCapture: (@Sendable () -> Void)? {
        get { _onCapture.withLock { $0 } }
        set { _onCapture.withLock { $0 = newValue } }
    }
    
    nonisolated var onCaptureComplete: (@Sendable () -> Void)? {
        get { _onCaptureComplete.withLock { $0 } }
        set { _onCaptureComplete.withLock { $0 = newValue } }
    }
    
    nonisolated var onQRCodeScanned: (@Sendable (String) -> Void)? {
        get { _onQRCodeScanned.withLock { $0 } }
        set { _onQRCodeScanned.withLock { $0 = newValue } }
    }
    
    nonisolated var onFocusLocked: (@Sendable () -> Void)? {
        get { _onFocusLocked.withLock { $0 } }
        set { _onFocusLocked.withLock { $0 = newValue } }
    }
    
    nonisolated var onStorageError: (@Sendable () -> Void)? {
        get { _onStorageError.withLock { $0 } }
        set { _onStorageError.withLock { $0 = newValue } }
    }
    
    nonisolated var frameReceiver: FrameReceiver? {
        get { _frameReceiver.withLock { $0.receiver } }
        set { _frameReceiver.withLock { $0.receiver = newValue } }
    }
    
    nonisolated var currentLocation: CLLocation? {
        get { _currentLocation.withLock { $0 } }
        set { _currentLocation.withLock { $0 = newValue } }
    }
    
    nonisolated var processingMode: ProcessingMode {
        get { _processingMode.withLock { $0 } }
        set { _processingMode.withLock { $0 = newValue } }
    }
    
    nonisolated var activeDeviceType: AVCaptureDevice.DeviceType {
        get { _activeDeviceType.withLock { $0 } }
        set { _activeDeviceType.withLock { $0 = newValue } }
    }
    
    nonisolated override init() { super.init() }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            var currentISO: Float = 100
            if let attachments = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any],
               let exif = attachments["{Exif}"] as? [String: Any],
               let isoArray = exif["ISOSpeedRatings"] as? [NSNumber],
               let isoValue = isoArray.first {
                currentISO = isoValue.floatValue
            }
            
            let deviceType = _activeDeviceType.withLock { $0 }
            let mode = _processingMode.withLock { $0 }
            
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let finalImage = filterPipeline.apply(to: rawImage, mode: mode, deviceType: deviceType, iso: currentISO)
            frameReceiver?.receive(image: finalImage)
        }
    }
    
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let qrObject = metadataObjects.first(where: { $0.type == .qr }) as? AVMetadataMachineReadableCodeObject,
              let stringValue = qrObject.stringValue else { return }
              
        let now = Date()
        let shouldProcess = _lastScannedQR.withLock { state -> Bool in
            if state.value == stringValue && now.timeIntervalSince(state.timestamp) < 2.0 {
                return false
            }
            state = (value: stringValue, timestamp: now)
            return true
        }
        
        if shouldProcess {
            onQRCodeScanned?(stringValue)
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        onCapture?()
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { onCaptureComplete?() }
        
        guard error == nil, let photoData = photo.fileDataRepresentation() else { return }
        
        var capturedISO: Float = 100
        if let exif = photo.metadata["{Exif}"] as? [String: Any],
           let isoArray = exif["ISOSpeedRatings"] as? [NSNumber],
           let isoValue = isoArray.first {
            capturedISO = isoValue.floatValue
        }
        
        let location = self.currentLocation
        let mode = self.processingMode
        let deviceType = self.activeDeviceType
        
        Task {
            do {
                try await PhotoProcessor.shared.processAndSave(photoData: photoData, location: location, context: OnyxGlobals.sharedContext, mode: mode, deviceType: deviceType, iso: capturedISO)
            } catch ProcessorError.insufficientStorage {
                onStorageError?()
            } catch {
                print("Failed with unknown error: \(error)")
            }
        }
    }
}
