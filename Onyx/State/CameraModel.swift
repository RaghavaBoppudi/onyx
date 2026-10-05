import AVFoundation
import SwiftUI

@MainActor
@Observable
final class CameraModel {

    enum Phase: Equatable {
        case idle, requestingAccess, denied, running, failed(String)
    }

    enum Pipeline: Equatable {
        case single, dual
    }

    private(set) var phase: Phase = .idle
    private(set) var pipeline: Pipeline = .single
    private(set) var lenses: [Lens] = []
    private(set) var selectedLens: Lens?
    private(set) var isBusy = false
    private(set) var isSwitching = false
    private(set) var isDualAvailable = false
    private(set) var selectedMode: CaptureMode = .standard
    private(set) var dualLayout: DualLayoutStyle = .pictureInPicture
    private(set) var ghostOverlay: UIImage?
    private(set) var blinkOpacity: Double = 0

    let reference = RotationTracker()
    let rotation = RotationTracker()
    let secondaryRotation = RotationTracker()
    let whiteBalance = WhiteBalanceReadiness()
    let recentPhoto = RecentPhotoWatcher()
    let location = LocationProvider()

    var isAwaitingSecondFrame: Bool { ghostOverlay != nil }

    var cameraPosition: AVCaptureDevice.Position { selectedLens?.position ?? .back }

    var visibleLenses: [Lens] { lenses.filter { $0.position == cameraPosition } }

    var hasFrontCamera: Bool { lenses.contains { $0.position == .front } }

    var canFlipCamera: Bool {
        hasFrontCamera && !selectedMode.isDual && !isAwaitingSecondFrame
    }

    var availableModes: [CaptureMode] {
        CaptureMode.allCases.filter { !$0.isDual || isDualAvailable }
    }

    var isOnDimmerLens: Bool {
        guard let lens = selectedLens, lens.position == .back else { return false }
        return abs(lens.factor - 1.0) >= 0.01
    }

    var sessionBox: CaptureSessionBox { engine.box }
    var dualBox: DualSessionBox { dualEngine.box }

    private struct DualLensPair {
        let rear: Lens
        let front: Lens
    }

    private let engine = CaptureEngine()
    private let dualEngine = DualCaptureEngine()
    private let renderer = ImageRenderer()
    private let library = PhotoLibraryWriter()
    private let settings: AppSettings
    private var lastLens: [AVCaptureDevice.Position: Lens] = [:]

    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    private var photoRotationAngle: CGFloat {
        guard let lens = selectedLens, FrontCameraPipeline.isCenterStage(lens) else {
            return reference.captureAngle
        }
        return FrontCameraPipeline.photoRotationAngle(reference: reference.captureAngle)
    }

    private var shotContext: ImageRenderer.Context {
        let isPortrait = abs(sin(reference.captureAngle * .pi / 180)) > 0.5
        return ImageRenderer.Context(source: cameraPosition, isPortrait: isPortrait)
    }

    private var dualFrontAngle: CGFloat {
        let angle = secondaryRotation.captureAngle
        guard let lens = Self.defaultLens(in: lenses, at: .front), FrontCameraPipeline.isCenterStage(lens) else {
            return angle
        }
        return FrontCameraPipeline.dualRotationAngle(device: angle)
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() async {
        await serialized { await self.performStart() }
    }

    func stop() async {
        await serialized { await self.performStop() }
    }

    func select(_ lens: Lens) async {
        await serialized { await self.performSelect(lens) }
    }

    func setMode(_ mode: CaptureMode) async {
        await serialized { await self.performSetMode(mode) }
    }

    func flipCamera() async {
        guard canFlipCamera else { return }

        let target: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        guard let lens = lastLens[target] ?? Self.defaultLens(in: lenses, at: target) else { return }

        await select(lens)
    }

    func updateDualLayout(_ style: DualLayoutStyle) {
        dualLayout = style
    }

    func cancelDoubleExposureSequence() {
        guard isAwaitingSecondFrame else { return }
        ghostOverlay = nil
        Task {
            await renderer.cancelDoubleExposure()
            try? await engine.restoreExposureBias()
        }
        Haptics.shared.fire(.failure)
    }

    func capture() async {
        guard phase == .running, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        if selectedMode.isDual {
            await captureDual()
        } else if selectedMode.isDoubleExposure, !isAwaitingSecondFrame {
            await captureFirstExposure()
        } else if let shot = await takePhoto(errorContext: "Capture") {
            await develop(shot)
        }
    }

    func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        Haptics.shared.fire(.toggle)
        UIApplication.shared.open(url)
    }

    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = lastOperation
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        lastOperation = task
        await task.value
    }

    private func performStart() async {
        guard phase != .running else { return }
        phase = .requestingAccess

        guard await engine.requestCameraAccess() else {
            phase = .denied
            return
        }

        lenses = LensCatalog.lenses()
        isDualAvailable = AVCaptureMultiCamSession.isMultiCamSupported
            && Self.dualPair(in: lenses) != nil

        #if targetEnvironment(simulator)
        if lenses.isEmpty {
            Log.capture.warning("No lenses discovered — proceeding in Simulator UI-preview mode")
            phase = .running
            return
        }
        #endif

        guard let initial = Self.defaultLens(in: lenses, at: .back) else {
            phase = .failed(CaptureError.noLensesAvailable.localizedDescription)
            return
        }

        apply(initial)
        reference.bind(to: initial)
        whiteBalance.bind(to: initial)

        if selectedMode.isDual {
            if !(await enterDual()) { selectedMode = .standard }
        } else {
            do {
                try await engine.select(lens: initial)
                pipeline = .single
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }

        if case .failed = phase { return }

        phase = .running
        Haptics.shared.prepare()
        location.start()
        Task { await renderer.warmUp() }
        Task { await recentPhoto.start() }
    }

    private func performStop() async {
        location.stop()
        await dualEngine.stop()
        await engine.stop()
        if phase == .running { phase = .idle }
    }

    private func performSelect(_ lens: Lens) async {
        guard lens.id != selectedLens?.id, !isSwitching, !selectedMode.isDual else { return }
        isSwitching = true
        defer { isSwitching = false }

        Haptics.shared.fire(.lensSwitch)
        do {
            try await engine.select(lens: lens)
            apply(lens)
        } catch {
            Haptics.shared.fire(.failure)
            Log.lens.error("Lens switch failed: \(error.localizedDescription)")
        }
    }

    private func performSetMode(_ mode: CaptureMode) async {
        guard mode != selectedMode, !isSwitching, !isBusy else { return }
        guard !mode.isDual || isDualAvailable else { return }

        isSwitching = true
        isBusy = true
        defer {
            isSwitching = false
            isBusy = false
        }

        if isAwaitingSecondFrame, !mode.isDoubleExposure {
            cancelDoubleExposureSequence()
        }

        switch (selectedMode.isDual, mode.isDual) {
        case (false, true):
            guard await enterDual() else { return }
        case (true, false):
            await exitDual()
        default:
            break
        }

        if !mode.isDual, mode.isDoubleExposure != selectedMode.isDoubleExposure {
            let isDoubleExposure = mode.isDoubleExposure
            Task {
                if isDoubleExposure {
                    try? await engine.setExposureBias(DoubleExposureProfile.exposureBias)
                } else {
                    try? await engine.restoreExposureBias()
                }
            }
        }

        selectedMode = mode
    }

    private func apply(_ lens: Lens) {
        selectedLens = lens
        lastLens[lens.position] = lens
        rotation.bind(to: lens)
    }

    private static func defaultLens(in lenses: [Lens], at position: AVCaptureDevice.Position) -> Lens? {
        let candidates = lenses.filter { $0.position == position }

        if position == .front {
            return candidates.min { $0.factor < $1.factor }
        }
        return candidates.min { abs($0.factor - 1.0) < abs($1.factor - 1.0) }
    }

    private static func dualPair(in lenses: [Lens]) -> DualLensPair? {
        guard let rear = defaultLens(in: lenses, at: .back),
              let front = defaultLens(in: lenses, at: .front)
        else { return nil }
        return DualLensPair(rear: rear, front: front)
    }

    private func enterDual() async -> Bool {
        guard let pair = Self.dualPair(in: lenses) else { return false }

        await engine.stop()

        do {
            try await dualEngine.start(rear: pair.rear, front: pair.front)
        } catch {
            Log.capture.error("Dual start failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            pipeline = .single
            await restoreSingle()
            return false
        }

        rotation.bind(to: pair.rear)
        secondaryRotation.bind(to: pair.front)
        whiteBalance.bind(to: pair.rear)
        pipeline = .dual
        return true
    }

    private func exitDual() async {
        await dualEngine.stop()
        pipeline = .single
        await restoreSingle()
    }

    private func restoreSingle() async {
        guard let lens = selectedLens else { return }

        do {
            try await engine.select(lens: lens)
            rotation.bind(to: lens)
            whiteBalance.bind(to: lens)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func captureDual() async {
        guard pipeline == .dual, let frames = dualEngine.frames.snapshot() else {
            Log.capture.error("Dual capture failed: no frames available")
            Haptics.shared.fire(.failure)
            return
        }

        fireShutterFeedback()

        do {
            let output = try await renderer.renderDual(
                frames,
                rearOrientation: CGImagePropertyOrientation(rotationAngle: rotation.captureAngle),
                frontOrientation: CGImagePropertyOrientation(rotationAngle: dualFrontAngle),
                style: dualLayout
            )
            try await library.save(heic: output.heic, location: location.latestLocation)
            Haptics.shared.fire(.success)
        } catch {
            Log.render.error("Dual develop failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
        }
    }

    private func captureFirstExposure() async {
        try? await engine.setExposureBias(DoubleExposureProfile.exposureBias)

        guard let shot = await takePhoto(errorContext: "First exposure") else {
            try? await engine.restoreExposureBias()
            return
        }

        do {
            let previewData = try await renderer.beginDoubleExposure(
                shot, mode: selectedMode, context: shotContext
            )
            guard let preview = UIImage(data: previewData) else {
                throw CaptureError.renderFailed("Could not build ghost overlay preview")
            }
            ghostOverlay = preview
            Haptics.shared.fire(.selection)
        } catch {
            Log.render.error("Double exposure hold failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            try? await engine.restoreExposureBias()
        }
    }

    private func takePhoto(errorContext: String) async -> RawCapture? {
        do {
            return try await engine.capturePhoto(
                rotationAngle: photoRotationAngle,
                flashMode: settings.flashMode,
                onShutterFire: {
                    Task { @MainActor [weak self] in self?.fireShutterFeedback() }
                }
            )
        } catch {
            Log.capture.error("\(errorContext) failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            return nil
        }
    }

    private func develop(_ shot: RawCapture) async {
        let wasFinishingDoubleExposure = isAwaitingSecondFrame
        let context = shotContext

        do {
            let output = wasFinishingDoubleExposure
                ? try await renderer.finishDoubleExposure(shot, mode: selectedMode, context: context)
                : try await renderer.render(shot, mode: selectedMode, context: context)
            ghostOverlay = nil

            try await library.save(heic: output.heic, location: location.latestLocation)
            Haptics.shared.fire(.success)

            Log.render.info("Developed via \(output.usedRAWPath ? "RAW" : "ISP fallback") path")
        } catch {
            Log.render.error("Develop failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            ghostOverlay = nil
        }

        if wasFinishingDoubleExposure {
            try? await engine.restoreExposureBias()
        }
    }

    private func fireShutterFeedback() {
        Haptics.shared.fire(.shutterFire)
        withAnimation(Metrics.Motion.blinkIn) { blinkOpacity = Metrics.Blink.opacity }
        withAnimation(Metrics.Motion.blinkOut.delay(Metrics.Blink.inDuration)) {
            blinkOpacity = 0
        }
    }
}
