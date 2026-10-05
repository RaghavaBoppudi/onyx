import AVFoundation
import os

nonisolated enum CaptureError: LocalizedError, Sendable, Equatable {
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
    case multiCamUnsupported
    case multiCamBudgetExceeded

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
        case .multiCamUnsupported:        "This device cannot run both cameras at once."
        case .multiCamBudgetExceeded:     "Both cameras cannot run together right now."
        }
    }
}

nonisolated enum CaptureConstants {
    static let rearExposureBias: Float = -0.7
    static let frontExposureBias: Float = 0
    static let colorSpace: AVCaptureColorSpace = .sRGB
    static let exposureConvergenceTimeout: Duration = .seconds(1)

    static func exposureBias(for position: AVCaptureDevice.Position) -> Float {
        position == .front ? frontExposureBias : rearExposureBias
    }
}

nonisolated final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

actor CaptureEngine {

    nonisolated let box = CaptureSessionBox()
    private var session: AVCaptureSession { box.session }

    private let sessionQueue = DispatchSerialQueue(label: "com.onyx.camera.session", qos: .userInitiated)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    private let photoOutput = AVCapturePhotoOutput()
    private var deviceInput: AVCaptureDeviceInput?
    private var activeDevice: AVCaptureDevice?
    private var activePosition: AVCaptureDevice.Position = .back
    private var bayerFormat: OSType?
    private var isOutputAttached = false
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]
    private var bayerFormatCache: [String: OSType?] = [:]

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

    func stop() async {
        try? await runExclusively { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func select(lens: Lens) async throws {
        try await runExclusively { [self] in try await activate(lens) }
    }

    func restoreExposureBias() async throws {
        try await setExposureBias(CaptureConstants.exposureBias(for: activePosition))
    }

    func setExposureBias(_ bias: Float) async throws {
        try await runExclusively { [self] in
            guard let device = activeDevice else {
                throw CaptureError.deviceUnavailable("active")
            }
            let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)

            do {
                try device.lockForConfiguration()
            } catch {
                throw CaptureError.configurationFailed(error.localizedDescription)
            }
            let applied = await BoundedCompletion.run(timeout: .seconds(1)) { finish in
                device.setExposureTargetBias(clamped) { _ in finish() }
            }
            device.unlockForConfiguration()
            if !applied { Log.capture.warning("Exposure bias update timed out") }

            let updates = device.values(of: \.isAdjustingExposure)
            await updates.waitFor(false, timeout: CaptureConstants.exposureConvergenceTimeout)
        }
    }

    private func activate(_ lens: Lens) async throws {
        try configure(for: lens)

        guard lens.position == .front, let device = activeDevice else { return }
        try await FrontCameraPipeline.applyPortraitAspectRatio(to: device)
    }

    private func configure(for lens: Lens) throws {
        guard let device = lens.resolveDevice() else {
            throw CaptureError.deviceUnavailable(lens.label)
        }

        if session.isRunning, activeDevice?.uniqueID == device.uniqueID {
            let zoom = FrontCameraPipeline.zoomFactor(for: lens, on: device)
            try device.withConfigurationLock {
                device.videoZoomFactor = RawPipeline.clampedZoom(zoom, for: device)
            }
            return
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
        activePosition = lens.position

        if !isOutputAttached {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw CaptureError.cannotAddOutput
            }
            session.addOutput(photoOutput)
            isOutputAttached = true
        }

        do {
            try prepare(device, for: lens)
        } catch {
            session.commitConfiguration()
            throw error
        }

        session.commitConfiguration()

        if !session.isRunning { session.startRunning() }

        if lens.position == .back, bayerFormat == nil {
            Log.capture.warning("\(lens.label): no Bayer RAW — look will sit on top of ISP output")
        }
        let side = lens.position == .front ? "front" : "rear"
        Log.lens.info("Configured \(lens.label) \(side), RAW: \(self.bayerFormat != nil)")
    }

    private func prepare(_ device: AVCaptureDevice, for lens: Lens) throws {
        if lens.position == .front {
            try FrontCameraPipeline.selectFormat(on: device)
        }

        RawPipeline.configure(output: photoOutput, device: device)
        bayerFormat = resolvedBayerFormat(for: lens, device: device)

        let zoom = FrontCameraPipeline.zoomFactor(for: lens, on: device)
        let bias = CaptureConstants.exposureBias(for: lens.position)
        try device.withConfigurationLock {
            RawPipeline.configure(device: device, zoomFactor: zoom, exposureBias: bias)
        }
    }

    private func resolvedBayerFormat(for lens: Lens, device: AVCaptureDevice) -> OSType? {
        guard lens.position == .back else { return nil }

        if let cached = bayerFormatCache[lens.id] { return cached }

        let resolved = RawPipeline.resolveBayerFormat(output: photoOutput, device: device)
        bayerFormatCache[lens.id] = resolved
        return resolved
    }

    func capturePhoto(
        request: CaptureRequest,
        onShutterFire: @escaping @Sendable () -> Void
    ) async throws -> RawCapture {
        try await runExclusively { [self] in
            try await performCapture(request: request, onShutterFire: onShutterFire)
        }
    }

    private func performCapture(
        request: CaptureRequest,
        onShutterFire: @escaping @Sendable () -> Void
    ) async throws -> RawCapture {
        guard activeDevice != nil else {
            throw CaptureError.deviceUnavailable("active")
        }

        let settings = RawPipeline.makeSettings(
            output: photoOutput, bayerFormat: bayerFormat, flashMode: request.flashMode
        )

        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(request.rotationAngle) {
                connection.videoRotationAngle = request.rotationAngle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        let processor = PhotoCaptureProcessor(
            orientation: request.orientation, onShutterFire: onShutterFire
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
