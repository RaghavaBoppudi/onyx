import AVFoundation

enum CaptureError: LocalizedError, Sendable, Equatable {
    case cameraAccessDenied
    case photoLibraryAccessDenied
    case noLensesAvailable
    case deviceUnavailable(String)
    case cannotAddInput
    case cannotAddOutput
    case configurationFailed(String)
    case captureFailed(String)
    case renderFailed(String)
    case noImageData

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:         "Onyx needs camera access to shoot."
        case .photoLibraryAccessDenied:   "Onyx needs permission to save to your library."
        case .noLensesAvailable:          "No usable camera was found on this device."
        case .deviceUnavailable(let l):   "The \(l) lens is unavailable."
        case .cannotAddInput:             "The camera input could not be attached."
        case .cannotAddOutput:            "The photo output could not be attached."
        case .configurationFailed(let m): "Camera setup failed: \(m)"
        case .captureFailed(let m):       "Capture failed: \(m)"
        case .renderFailed(let m):        "Could not develop the photo: \(m)"
        case .noImageData:                "The capture returned no image data."
        }
    }
}

enum CaptureConstants {
    static let exposureBias: Float = -0.3
    static let colorSpace: AVCaptureColorSpace = .sRGB
    /// Ceiling on how long setExposureBias waits for isAdjustingExposure to
    /// clear before giving up and letting capture proceed anyway. A capture
    /// path should never be able to hang indefinitely on AE convergence.
    static let exposureConvergenceTimeout: Duration = .seconds(1)
}

final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

actor CaptureEngine {

    nonisolated let box = CaptureSessionBox()
    private var session: AVCaptureSession { box.session }

    private let photoOutput = AVCapturePhotoOutput()
    private var deviceInput: AVCaptureDeviceInput?
    private var activeDevice: AVCaptureDevice?
    private var bayerFormat: OSType?
    private var isOutputAttached = false
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]
    private var bayerFormatCache: [String: OSType?] = [:]

    var deliversRAW: Bool { bayerFormat != nil }

    nonisolated func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private var lastOperation: Task<Void, Never>?

    @discardableResult
    private func runExclusively<T: Sendable>(
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        let previous = lastOperation
        let task = Task<Result<T, Error>, Never> {
            _ = await previous?.value
            do { return .success(try await operation()) }
            catch { return .failure(error) }
        }
        lastOperation = Task { _ = await task.value }
        return try await task.value.get()
    }

    func start(with lens: Lens) async throws {
        try await runExclusively { [self] in try configure(for: lens) }
    }

    func stop() async {
        try? await runExclusively { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func select(lens: Lens) async throws {
        try await runExclusively { [self] in try configure(for: lens) }
    }

    /// Sets an absolute exposure target bias on the active device and waits
    /// for the sensor to actually converge to it before returning — setting
    /// the bias alone only *requests* the change; isAdjustingExposure is what
    /// confirms the device has caught up, same pattern WhiteBalanceReadiness
    /// already uses for white balance. Capped at
    /// CaptureConstants.exposureConvergenceTimeout so a scene that never
    /// fully settles can't hang a capture.
    ///
    /// NOTE: this only has an effect in .autoExpose or .continuousAutoExposure
    /// mode. If RawPipeline.configure(device:) puts the device in .locked or
    /// .custom exposure mode, this call may be a silent no-op — check the
    /// per-capture exposure log in performCapture() below to confirm whether
    /// it actually reached the sensor.
    ///
    /// This replaces whatever bias is currently set — including
    /// CaptureConstants.exposureBias, the normal baseline — it does not stack
    /// with it. Callers are responsible for resetting back to
    /// CaptureConstants.exposureBias when done.
    func setExposureBias(_ bias: Float) async throws {
        try await runExclusively { [self] in
            guard let device = activeDevice else {
                throw CaptureError.deviceUnavailable("active")
            }
            do {
                try device.lockForConfiguration()
            } catch {
                throw CaptureError.configurationFailed(error.localizedDescription)
            }

            let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                device.setExposureTargetBias(clamped) { _ in continuation.resume() }
            }
            device.unlockForConfiguration()

            await Self.waitForExposureConvergence(device: device)

            Log.capture.debug(
                "setExposureBias(\(bias)) → mode: \(device.exposureMode.rawValue), targetBias now: \(device.exposureTargetBias)"
            )
        }
    }

    private static func waitForExposureConvergence(device: AVCaptureDevice) async {
        guard device.isAdjustingExposure else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    var observation: NSKeyValueObservation?
                    observation = device.observe(\.isAdjustingExposure, options: [.new]) { _, change in
                        guard change.newValue == false else { return }
                        observation?.invalidate()
                        continuation.resume()
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: CaptureConstants.exposureConvergenceTimeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func configure(for lens: Lens) throws {
        guard let device = lens.resolveDevice() else {
            throw CaptureError.deviceUnavailable(lens.label)
        }

        session.beginConfiguration()

        session.sessionPreset = .photo

        if let existing = deviceInput { session.removeInput(existing) }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            if let existing = deviceInput { session.addInput(existing) }
            session.commitConfiguration()
            throw CaptureError.configurationFailed(error.localizedDescription)
        }

        guard session.canAddInput(input) else {
            if let existing = deviceInput { session.addInput(existing) }
            session.commitConfiguration()
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)
        deviceInput = input
        activeDevice = device

        if !isOutputAttached {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw CaptureError.cannotAddOutput
            }
            session.addOutput(photoOutput)
            isOutputAttached = true
        }

        RawPipeline.configure(output: photoOutput, device: device)

        if let cached = bayerFormatCache[lens.id] {
            bayerFormat = cached
        } else {
            let resolved = RawPipeline.resolveBayerFormat(output: photoOutput, device: device)
            bayerFormatCache[lens.id] = resolved
            bayerFormat = resolved
        }

        do {
            try device.lockForConfiguration()
            RawPipeline.configure(device: device)
            device.unlockForConfiguration()
        } catch {
            session.commitConfiguration()
            throw CaptureError.configurationFailed(error.localizedDescription)
        }

        session.commitConfiguration()

        if !session.isRunning { session.startRunning() }

        if bayerFormat == nil {
            Log.capture.warning("\(lens.label): no Bayer RAW — look will sit on top of ISP output")
        }
        Log.lens.info("Configured \(lens.label), RAW: \(self.bayerFormat != nil)")
    }

    func capturePhoto(
        rotationAngle: CGFloat,
        flashMode: AVCaptureDevice.FlashMode,
        onShutterFire: @escaping @Sendable () -> Void
    ) async throws -> RawCapture {
        try await runExclusively { [self] in
            try await performCapture(
                rotationAngle: rotationAngle, flashMode: flashMode, onShutterFire: onShutterFire
            )
        }
    }

    private func performCapture(
        rotationAngle: CGFloat,
        flashMode: AVCaptureDevice.FlashMode,
        onShutterFire: @escaping @Sendable () -> Void
    ) async throws -> RawCapture {
        guard let device = activeDevice else {
            throw CaptureError.deviceUnavailable("active")
        }

        // Diagnostic: confirms what the sensor is actually doing at the
        // instant of capture, independent of whatever setExposureBias
        // requested. exposureMode 0 = locked, 1 = autoExpose,
        // 2 = continuousAutoExposure, 3 = custom. If mode is 0 or 3 while a
        // double exposure is in progress, that's why bias isn't taking effect.
        Log.capture.debug(
            "Capturing — exposureMode: \(device.exposureMode.rawValue), targetBias: \(device.exposureTargetBias), ISO: \(device.iso), duration: \(device.exposureDuration.seconds)s"
        )

        let settings = RawPipeline.makeSettings(
            output: photoOutput, bayerFormat: bayerFormat, flashMode: flashMode
        )

        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }

        let orientation = OrientationResolver.exifOrientation(forRotationAngle: rotationAngle)
        let processor = PhotoCaptureProcessor(
            orientation: orientation, onShutterFire: onShutterFire
        )

        let id = settings.uniqueID
        inFlight[id] = processor
        defer { inFlight[id] = nil }

        return try await withCheckedThrowingContinuation { continuation in
            processor.attach(continuation)
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }
}
