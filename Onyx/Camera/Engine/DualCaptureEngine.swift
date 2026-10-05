import AVFoundation
import os

nonisolated final class DualSessionBox: @unchecked Sendable {
    let session: AVCaptureMultiCamSession
    let rearPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    init() {
        let session = AVCaptureMultiCamSession()
        self.session = session
        rearPreviewLayer = Self.makePreviewLayer(for: session)
        frontPreviewLayer = Self.makePreviewLayer(for: session)
    }

    private static func makePreviewLayer(for session: AVCaptureSession) -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

actor DualCaptureEngine {

    nonisolated let box = DualSessionBox()
    nonisolated let frames = DualFrameStore()

    private nonisolated struct Source {
        let device: AVCaptureDevice
        let format: AVCaptureDevice.Format
        let zoomFactor: CGFloat
    }

    private var session: AVCaptureMultiCamSession { box.session }

    func start(rear rearLens: Lens, front frontLens: Lens) throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CaptureError.multiCamUnsupported
        }
        guard let rearDevice = rearLens.resolveDevice() else {
            throw CaptureError.deviceUnavailable(rearLens.label)
        }
        guard let frontDevice = frontLens.resolveDevice() else {
            throw CaptureError.deviceUnavailable("front")
        }

        shutDown()

        let rearFormats = Self.candidateFormats(for: rearDevice)
        let frontFormats = Self.candidateFormats(for: frontDevice)
        guard !rearFormats.isEmpty, !frontFormats.isEmpty else {
            throw CaptureError.multiCamUnsupported
        }

        let rearZoom = FrontCameraPipeline.zoomFactor(for: rearLens, on: rearDevice)
        let frontZoom = FrontCameraPipeline.zoomFactor(for: frontLens, on: frontDevice)

        for level in 0..<max(rearFormats.count, frontFormats.count) {
            let rear = Source(
                device: rearDevice,
                format: rearFormats[min(level, rearFormats.count - 1)],
                zoomFactor: rearZoom
            )
            let front = Source(
                device: frontDevice,
                format: frontFormats[min(level, frontFormats.count - 1)],
                zoomFactor: frontZoom
            )

            do {
                try configure(rear: rear, front: front)
            } catch {
                tearDown()
                throw error
            }

            if isWithinBudget {
                session.startRunning()
                Log.capture.info("Dual session running, hardware cost \(self.session.hardwareCost)")
                return
            }

            tearDown()
        }

        throw CaptureError.multiCamBudgetExceeded
    }

    func stop() {
        shutDown()
    }

    private var isWithinBudget: Bool {
        session.hardwareCost <= 1.0 && session.systemPressureCost <= 1.0
    }

    private func configure(rear: Source, front: Source) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        try attach(
            rear,
            output: frames.rearOutput,
            previewLayer: box.rearPreviewLayer,
            mirrorsPreview: false
        )
        try attach(
            front,
            output: frames.frontOutput,
            previewLayer: box.frontPreviewLayer,
            mirrorsPreview: true
        )
    }

    private func attach(
        _ source: Source,
        output: AVCaptureVideoDataOutput,
        previewLayer: AVCaptureVideoPreviewLayer,
        mirrorsPreview: Bool
    ) throws {
        let device = source.device
        let bias = CaptureConstants.exposureBias(for: device.position)

        try device.withConfigurationLock {
            device.activeFormat = source.format
            RawPipeline.configure(device: device, zoomFactor: source.zoomFactor, exposureBias: bias)
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.configurationFailed(error.localizedDescription)
        }

        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInputWithNoConnections(input)

        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutputWithNoConnections(output)

        guard let port = input.ports(
            for: .video,
            sourceDeviceType: device.deviceType,
            sourceDevicePosition: device.position
        ).first else { throw CaptureError.cannotAddInput }

        let dataConnection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(dataConnection) else { throw CaptureError.cannotAddOutput }
        session.addConnection(dataConnection)
        if dataConnection.isVideoMirroringSupported {
            dataConnection.automaticallyAdjustsVideoMirroring = false
            dataConnection.isVideoMirrored = false
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { throw CaptureError.cannotAddOutput }
        session.addConnection(previewConnection)
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = mirrorsPreview
        }
    }

    private func shutDown() {
        if session.isRunning { session.stopRunning() }
        tearDown()
    }

    private func tearDown() {
        session.beginConfiguration()
        for connection in session.connections { session.removeConnection(connection) }
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
        session.commitConfiguration()
        frames.reset()
    }

    private static func candidateFormats(for device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        let supported = device.formats.filter(\.isMultiCamSupported)
        let preferred = supported.filter(\.isSquareOrFourByThree)
        let pool = preferred.isEmpty ? supported : preferred

        var seen = Set<Int>()
        return pool
            .sorted { $0.videoPixelCount > $1.videoPixelCount }
            .filter { seen.insert($0.videoPixelCount).inserted }
    }
}

private extension AVCaptureDevice.Format {
    nonisolated var videoPixelCount: Int {
        let dimensions = formatDescription.dimensions
        return Int(dimensions.width) * Int(dimensions.height)
    }

    nonisolated var isSquareOrFourByThree: Bool {
        let dimensions = formatDescription.dimensions
        guard dimensions.height > 0 else { return false }
        let ratio = Double(dimensions.width) / Double(dimensions.height)
        return abs(ratio - 1) < 0.01 || abs(ratio - 4.0 / 3.0) < 0.01 || abs(ratio - 3.0 / 4.0) < 0.01
    }
}
