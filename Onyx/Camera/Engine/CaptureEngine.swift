//  CaptureEngine.swift
//  Owns the AVCaptureSession. Nothing here runs on the main thread.
//
//  There is deliberately no AVCaptureVideoDataOutput: no delegate callback can race
//  `beginConfiguration()`, which is the whole class of hang that appears when
//  filtering runs on a video queue during a lens swap. Preview-layer apps built
//  against iOS 26+ also get Deferred Start for free.
//
//  CaptureError and the fixed capture constants live here rather than in their own
//  files — both exist for, and only for, this actor and RawPipeline. A one-enum
//  file and a three-constant file were separate types wearing separate files for no
//  reason a reader could find; the split cost more in navigation than it bought in
//  isolation, since nothing about either changes independently of this file.

import AVFoundation

// MARK: - Errors

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

// MARK: - Fixed capture values

/// Everything that shapes the image and isn't a user-facing option. Onyx has no
/// capture settings by design — this, plus `LookProfile`, is the whole knob set.
enum CaptureConstants {
    /// Fixed negative bias. With a firm shoulder in the curve there is no highlight
    /// recovery downstream, so highlights are protected at the sensor.
    static let exposureBias: Float = -0.5
    /// Affects the preview and the ISP fallback path only; the RAW decoder works in
    /// its own space.
    static let colorSpace: AVCaptureColorSpace = .sRGB
}

// MARK: - Session box

/// AVCaptureSession is not `Sendable`; this box lets the preview layer read it from
/// the main actor without crossing isolation.
final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

// MARK: - Engine

actor CaptureEngine {

    nonisolated let box = CaptureSessionBox()
    private var session: AVCaptureSession { box.session }

    private let photoOutput = AVCapturePhotoOutput()
    private var deviceInput: AVCaptureDeviceInput?
    private var activeDevice: AVCaptureDevice?
    private var bayerFormat: OSType?
    private var isOutputAttached = false
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    /// Answer, per lens, to "does this optic expose Bayer RAW on some format?" —
    /// probing this means iterating every `AVCaptureDevice.Format` and locking
    /// configuration on candidates one at a time, which is real cost. Without this
    /// cache, switching 0.5x → 1x → 0.5x paid that cost twice for two answers it
    /// already had. `OSType??` is deliberate: the outer optional is "have we probed
    /// this lens," the inner is "did probing find RAW" — a lens with no RAW is a
    /// cached `nil`, not an unprobed one.
    private var bayerFormatCache: [String: OSType?] = [:]

    var deliversRAW: Bool { bayerFormat != nil }

    nonisolated func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    // MARK: - Reentrancy guard
    //
    // Actors are reentrant: an `await` inside one call lets another call run in the
    // gap before the first resumes. `capturePhoto` suspends for the length of the
    // exposure — a delegate callback resumes its continuation — and in that gap
    // `select(lens:)` could call `session.beginConfiguration()` and swap the input
    // device out from under a capture AVFoundation is still processing against the
    // old one. That's not merely untidy; AVFoundation makes no guarantee about what
    // happens to a photo request whose input disappears mid-flight, and this is
    // reachable from the UI as it stands — tap the shutter, then immediately tap a
    // different lens.
    //
    // `runExclusively` gives every mutating operation a real FIFO queue across
    // suspension points, which actor isolation alone does not provide. This is the
    // standard fix for this exact class of hazard, not a bespoke one.

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

    // MARK: - Lifecycle

    func start(with lens: Lens) async throws {
        try await runExclusively { [self] in try configure(for: lens) }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    func select(lens: Lens) async throws {
        try await runExclusively { [self] in try configure(for: lens) }
    }

    // MARK: - Configuration

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

        // Format probing has to happen inside the configuration block: changing
        // activeFormat outside one would restart the session mid-flight.
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

    // MARK: - Capture

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
        guard activeDevice != nil else {
            throw CaptureError.deviceUnavailable("active")
        }

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
