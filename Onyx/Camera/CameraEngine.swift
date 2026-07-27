@preconcurrency import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreLocation
import os

struct WeakReceiverBox: Sendable { weak var receiver: FrameReceiver? }

actor CameraEngine {
    private var session: AVCaptureSession!
    private let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue")
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let captureDelegate = EngineCaptureDelegate()
    private let locationProvider = LocationProvider()
    
    var availableLenses: [Lens] = []
    var currentLens: Lens?
    var currentMode: ProcessingMode = .zero
    
    // Default to 0.0 EV to maximize signal-to-noise ratio
    var exposureCompensation: Float = 0.0
    
    private var deviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false
    private var notificationTask: Task<Void, Never>?
    private var pressureObservation: NSKeyValueObservation?

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
    
    func setProcessingPipeline(mode: ProcessingMode) {
        self.currentMode = mode
        captureDelegate.processingMode = mode
        self.exposureCompensation = 0.0
        applyCurrentExposureBias()
    }
    
    func setExposureBias(_ bias: Float) {
        self.exposureCompensation = bias
        applyCurrentExposureBias()
    }
    
    private func applyCurrentExposureBias() {
        guard let device = deviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, exposureCompensation)), completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for exposure bias update.")
        }
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
            
            device.isSubjectAreaChangeMonitoringEnabled = true
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
            
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for continuous focus reset.")
        }
    }
    
    func start() async -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return false }
        } else if authStatus != .authorized {
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
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        configureInput()
        configureVideoOutput()
        configurePhotoOutput()
        configureMetadataOutput()
        
        session.commitConfiguration()
        
        if let device = deviceInput?.device {
            updatePhotoOutputDimensions(for: device)
            observeSystemPressure(for: device)
        }
        
        notificationTask?.cancel()
        notificationTask = Task {
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification) {
                resetFocusToContinuous()
            }
        }
        
        sessionQueue.async { [weak session] in
            session?.startRunning()
        }
        
        isConfigured = true
        return true
    }
    
    func stop() {
        notificationTask?.cancel()
        notificationTask = nil
        pressureObservation?.invalidate()
        pressureObservation = nil
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
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }
    
    private func configurePhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if photoOutput.isAppleProRAWSupported { photoOutput.isAppleProRAWEnabled = true }
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
        
        let preferredType: AVCaptureDevice.DeviceType = (position == .front) ? .builtInUltraWideCamera : .builtInWideAngleCamera
        
        let newLens = availableLenses.first(where: { $0.type == preferredType })
            ?? availableLenses.first(where: { $0.type == .builtInWideAngleCamera })
            ?? availableLenses.first
            
        if let lens = newLens { selectLens(lens) }
        return newLens
    }
    
    func selectLens(_ lens: Lens) {
        currentLens = lens
        captureDelegate.activeDeviceType = lens.type
        
        var currentChromaticity: AVCaptureDevice.WhiteBalanceChromaticityValues?
        if let currentDevice = deviceInput?.device {
            let currentGains = currentDevice.deviceWhiteBalanceGains
            currentChromaticity = currentDevice.chromaticityValues(for: currentGains)
        }
        
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
        
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: newDevice, previewLayer: nil)
        applySettings(to: newDevice, inheritedChromaticity: currentChromaticity)
        session.commitConfiguration()
        updatePhotoOutputDimensions(for: newDevice)
        observeSystemPressure(for: newDevice)
        
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
    }
    
    private func observeSystemPressure(for device: AVCaptureDevice) {
        pressureObservation?.invalidate()
        pressureObservation = device.observe(\.systemPressureState, options: [.new]) { device, _ in
            let pressureLevel = device.systemPressureState.level
            
            do {
                try device.lockForConfiguration()
                if pressureLevel == .serious || pressureLevel == .critical {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 20)
                } else if pressureLevel == .nominal || pressureLevel == .fair {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                }
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock device for thermal throttling.")
            }
        }
    }
    
    private func applySettings(to device: AVCaptureDevice, inheritedChromaticity: AVCaptureDevice.WhiteBalanceChromaticityValues? = nil) {
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
            
            if let chromaticity = inheritedChromaticity, device.isWhiteBalanceModeSupported(.locked) {
                let mappedGains = device.deviceWhiteBalanceGains(for: chromaticity)
                let maxGain = device.maxWhiteBalanceGain
                let clampedGains = AVCaptureDevice.WhiteBalanceGains(
                    redGain: min(max(1.0, mappedGains.redGain), maxGain),
                    greenGain: min(max(1.0, mappedGains.greenGain), maxGain),
                    blueGain: min(max(1.0, mappedGains.blueGain), maxGain)
                )
                
                device.setWhiteBalanceModeLocked(with: clampedGains) { _ in
                    Task {
                        do {
                            try device.lockForConfiguration()
                            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                                device.whiteBalanceMode = .continuousAutoWhiteBalance
                            }
                            device.unlockForConfiguration()
                        } catch {}
                    }
                }
            } else {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
            
            device.setExposureTargetBias(max(device.minExposureTargetBias, min(device.maxExposureTargetBias, exposureCompensation)), completionHandler: nil)
            device.isSubjectAreaChangeMonitoringEnabled = true
            
            if device.position == .front {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            } else {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            }
            device.unlockForConfiguration()
        } catch {}
    }
    
    private func updatePhotoOutputDimensions(for device: AVCaptureDevice) {
        if #available(iOS 16.0, *) {
            let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? CMVideoDimensions(width: 0, height: 0)
            photoOutput.maxPhotoDimensions = maxDimensions
        }
    }
    
    func capturePhoto(flashEnabled: Bool) {
        if let photoConnection = photoOutput.connection(with: .video), let coordinator = rotationCoordinator {
            let captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            if photoConnection.isVideoRotationAngleSupported(captureAngle) { photoConnection.videoRotationAngle = captureAngle }
        }
        
        let settings: AVCapturePhotoSettings
        let isZero = (currentMode == .zero || currentMode == .mono)
        
        if isZero {
            guard let bayerFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) else { return }
            settings = AVCapturePhotoSettings(rawPixelFormatType: bayerFormat)
        } else {
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
        }
        
        settings.isAutoRedEyeReductionEnabled = false
        settings.flashMode = flashEnabled ? .on : .off
        
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
    
    let ciContext = MTLCreateSystemDefaultDevice().map {
        CIContext(mtlDevice: $0, options: [.cacheIntermediates: false, .priorityRequestLow: false])
    } ?? CIContext(options: [.cacheIntermediates: false])

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
        
        let context = self.ciContext
        let location = self.currentLocation
        let mode = self.processingMode
        let deviceType = self.activeDeviceType
        
        Task { await PhotoProcessor.shared.processAndSave(photoData: photoData, location: location, context: context, mode: mode, deviceType: deviceType, iso: capturedISO) }
    }
}
