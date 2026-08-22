@preconcurrency import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreLocation
import os
import Photos

struct WeakReceiverBox: Sendable { weak var receiver: FrameReceiver? }

actor CameraEngine {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue")
    
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
    
    func setFocus(point: CGPoint) {
        guard let activeDevice = deviceInput?.device else { return }
        
        sessionQueue.async {
            do {
                try activeDevice.lockForConfiguration()
                if activeDevice.isFocusPointOfInterestSupported { activeDevice.focusPointOfInterest = point }
                if activeDevice.isFocusModeSupported(.continuousAutoFocus) { activeDevice.focusMode = .continuousAutoFocus }
                if activeDevice.isExposurePointOfInterestSupported { activeDevice.exposurePointOfInterest = point }
                if activeDevice.isExposureModeSupported(.continuousAutoExposure) { activeDevice.exposureMode = .continuousAutoExposure }
                if activeDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { activeDevice.whiteBalanceMode = .continuousAutoWhiteBalance }
                if activeDevice.isFocusPointOfInterestSupported || activeDevice.isExposurePointOfInterestSupported {
                    activeDevice.isSubjectAreaChangeMonitoringEnabled = true
                }
                activeDevice.unlockForConfiguration()
            } catch {
                print("Failed to lock device for focus update.")
            }
        }
    }
    
    func resetFocusToContinuous() {
        guard let activeDevice = deviceInput?.device else { return }
        
        sessionQueue.async {
            do {
                try activeDevice.lockForConfiguration()
                if activeDevice.isFocusPointOfInterestSupported { activeDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                if activeDevice.isFocusModeSupported(.continuousAutoFocus) { activeDevice.focusMode = .continuousAutoFocus }
                if activeDevice.isExposurePointOfInterestSupported { activeDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                if activeDevice.isExposureModeSupported(.continuousAutoExposure) { activeDevice.exposureMode = .continuousAutoExposure }
                if activeDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { activeDevice.whiteBalanceMode = .continuousAutoWhiteBalance }
                if activeDevice.isFocusPointOfInterestSupported || activeDevice.isExposurePointOfInterestSupported {
                    activeDevice.isSubjectAreaChangeMonitoringEnabled = true
                }
                activeDevice.unlockForConfiguration()
            } catch {
                print("Failed to lock device for continuous focus reset.")
            }
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
        
        guard !isConfigured else {
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
            }
            return true
        }
        
        session.automaticallyConfiguresApplicationAudioSession = false
        
        availableLenses = CameraHardware.availableLenses(for: .back)
        let initialLens = availableLenses.first(where: { $0.label == "1x" }) ?? availableLenses.first
        currentLens = initialLens
        captureDelegate.activeDeviceType = initialLens?.type ?? .builtInWideAngleCamera
        
        guard let lens = initialLens,
              let device = AVCaptureDevice.default(lens.type, for: .video, position: lens.position),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
              
        self.deviceInput = input
        let zoomFactor = lens.videoZoomFactor
        
        let success: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async { [session, videoOutput, photoOutput, metadataOutput, captureDelegate] in
                session.beginConfiguration()
                session.sessionPreset = .photo
                
                if session.canAddInput(input) { session.addInput(input) }
                
                videoOutput.setSampleBufferDelegate(captureDelegate, queue: DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive))
                videoOutput.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
                
                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                    if connection.isVideoMirroringSupported { connection.isVideoMirrored = (device.position == .front) }
                }
                
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                    if #available(iOS 17.0, *) {
                        photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported
                    }
                }
                
                if session.canAddOutput(metadataOutput) {
                    session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(captureDelegate, queue: DispatchQueue(label: "com.onyx.metadataQueue", qos: .userInitiated))
                    if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                        metadataOutput.metadataObjectTypes = [.qr]
                    }
                }
                
                // CRITICAL: Commit configuration before mutating device properties to prevent thread starvation
                session.commitConfiguration()
                
                do {
                    try device.lockForConfiguration()
                    if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                    if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
                    device.setExposureTargetBias(-0.5, completionHandler: nil)
                    device.videoZoomFactor = zoomFactor
                    if device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported {
                        device.isSubjectAreaChangeMonitoringEnabled = true
                    }
                    device.unlockForConfiguration()
                } catch {}
                
                // Resume immediately so UI loads instantly. Start hardware sequentially.
                continuation.resume(returning: true)
                session.startRunning()
            }
        }
        
        guard success else { return false }
        
        Task {
            let coordinator = await MainActor.run { AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil) }
            self.rotationCoordinator = coordinator
        }
        observeFocus(for: device)
        
        notificationTask?.cancel()
        notificationTask = Task {
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification) {
                await self.resetFocusToContinuous()
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
    
    func switchCameraPosition(to position: AVCaptureDevice.Position) -> Lens? {
        availableLenses = CameraHardware.availableLenses(for: position)
        let newLens = availableLenses.first(where: { $0.label == "1x" }) ?? availableLenses.first
            
        if let lens = newLens { selectLens(lens) }
        return newLens
    }
    
    func selectLens(_ lens: Lens) {
        let oldLens = currentLens
        currentLens = lens
        captureDelegate.activeDeviceType = lens.type
        
        let requiresInputRebuild: Bool
        if lens.position != oldLens?.position {
            requiresInputRebuild = true
        } else if lens.type != oldLens?.type {
            requiresInputRebuild = true
        } else {
            requiresInputRebuild = false
        }
        
        if requiresInputRebuild {
            guard let newDevice = AVCaptureDevice.default(lens.type, for: .video, position: lens.position),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
                  
            let oldInput = self.deviceInput
            self.deviceInput = newInput
            let zoomFactor = lens.videoZoomFactor
            
            sessionQueue.async { [session, videoOutput] in
                session.beginConfiguration()
                
                if let old = oldInput { session.removeInput(old) }
                if session.canAddInput(newInput) { session.addInput(newInput) }
                
                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
                    if connection.isVideoMirroringSupported { connection.isVideoMirrored = (newDevice.position == .front) }
                }
                
                // CRITICAL: Commit configuration before mutating new hardware
                session.commitConfiguration()
                
                do {
                    try newDevice.lockForConfiguration()
                    if newDevice.isFocusPointOfInterestSupported { newDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if newDevice.isFocusModeSupported(.continuousAutoFocus) { newDevice.focusMode = .continuousAutoFocus }
                    if newDevice.isExposurePointOfInterestSupported { newDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if newDevice.isExposureModeSupported(.continuousAutoExposure) { newDevice.exposureMode = .continuousAutoExposure }
                    if newDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { newDevice.whiteBalanceMode = .continuousAutoWhiteBalance }
                    newDevice.setExposureTargetBias(-0.5, completionHandler: nil)
                    newDevice.videoZoomFactor = zoomFactor
                    if newDevice.isFocusPointOfInterestSupported || newDevice.isExposurePointOfInterestSupported {
                        newDevice.isSubjectAreaChangeMonitoringEnabled = true
                    }
                    newDevice.unlockForConfiguration()
                } catch {}
            }
            
            Task {
                let coordinator = await MainActor.run { AVCaptureDevice.RotationCoordinator(device: newDevice, previewLayer: nil) }
                self.rotationCoordinator = coordinator
            }
            observeFocus(for: newDevice)
        } else {
            if let activeDevice = deviceInput?.device {
                sessionQueue.async {
                    do {
                        try activeDevice.lockForConfiguration()
                        activeDevice.videoZoomFactor = lens.videoZoomFactor
                        activeDevice.unlockForConfiguration()
                    } catch {}
                }
            }
        }
    }
    
    private func observeFocus(for device: AVCaptureDevice) {
        focusObservation?.invalidate()
        focusObservation = device.observe(\.isAdjustingFocus, options: [.old, .new]) { [weak self] device, change in
            guard let old = change.oldValue, let new = change.newValue, old == true, new == false else { return }
            Task { [weak self] in await self?.captureDelegate.onFocusLocked?() }
        }
    }
    
    func capturePhoto(flashEnabled: Bool) {
        if let photoConnection = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *), let coordinator = rotationCoordinator {
                let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                if photoConnection.isVideoRotationAngleSupported(captureAngle) { photoConnection.videoRotationAngle = captureAngle }
            } else {
                if photoConnection.isVideoOrientationSupported {
                    photoConnection.videoOrientation = .portrait
                }
            }
        }
        
        let settings: AVCapturePhotoSettings
        if let bayerFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: bayerFormat)
        } else {
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
            
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let finalImage = filterPipeline.apply(to: rawImage, deviceType: deviceType, iso: currentISO)
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
        let deviceType = self.activeDeviceType
        
        Task {
            do {
                try await PhotoProcessor.shared.processAndSave(photoData: photoData, location: location, context: OnyxGlobals.sharedContext, deviceType: deviceType, iso: capturedISO)
            } catch ProcessorError.insufficientStorage {
                onStorageError?()
            } catch {
                print("Failed with unknown error: \(error)")
            }
        }
    }
}
