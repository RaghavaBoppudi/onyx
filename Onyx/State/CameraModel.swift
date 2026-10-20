import AVFoundation
import CoreLocation
import SwiftUI
import os

enum Notice: Equatable {
    case saveFailed
    case captureFailed
    case lensSwitchFailed(String)
    case effectUnavailable(String)
    case locationDenied

    var message: String {
        switch self {
        case .saveFailed: "That photo couldn't be saved."
        case .captureFailed: "That photo couldn't be taken."
        case .lensSwitchFailed(let target): "Couldn't switch to the \(target)."
        case .effectUnavailable(let mode): "\(mode) couldn't be applied to that photo."
        case .locationDenied: "Allow Location access in Settings to add where you took your photos."
        }
    }

    var showsSettings: Bool { self == .locationDenied }
    var dismissesAutomatically: Bool { !showsSettings }
}

@MainActor
@Observable
final class CameraModel {

    enum Phase: Equatable {
        case idle, running, failed(String)
    }

    enum Pipeline: Equatable {
        case single, dual
    }

    enum Activity: Equatable {
        case idle, switching, changingMode, capturing
    }

    private enum ExposureSequence {
        case none
        case awaitingSecond(ghost: UIImage)
    }

    private(set) var phase: Phase = .idle
    private(set) var pipeline: Pipeline = .single
    private(set) var activity: Activity = .idle
    private(set) var developingCount = 0
    private(set) var notice: Notice?
    private(set) var pendingLensID: String?
    private(set) var lenses: [Lens] = []
    private(set) var selectedLens: Lens?
    private(set) var isDualAvailable = false
    private(set) var selectedMode: CaptureMode = .standard
    private(set) var dualLayout: DualLayoutStyle = .pictureInPicture
    private(set) var blinkOpacity: Double = 0
    private(set) var feedback: FeedbackEvent = .none

    private var exposureSequence: ExposureSequence = .none

    let reference = RotationTracker()
    let rotation = RotationTracker()
    let secondaryRotation = RotationTracker()
    let whiteBalance = WhiteBalanceReadiness()
    let recentPhoto = RecentPhotoWatcher()
    let location = LocationProvider()

    private let developLimit = 3

    var acceptsShutter: Bool {
        phase == .running
            && activity == .idle
            && developingCount < developLimit
    }

    var isShutterDimmed: Bool {
        activity == .capturing || developingCount >= developLimit
    }
    var isSwitching: Bool { activity == .switching }
    var isDeveloping: Bool { developingCount > 0 }

    var ghostOverlay: UIImage? {
        if case .awaitingSecond(let ghost) = exposureSequence { ghost } else { nil }
    }

    var isAwaitingSecondFrame: Bool { ghostOverlay != nil }

    var cameraPosition: AVCaptureDevice.Position { selectedLens?.position ?? .back }

    var visibleLenses: [Lens] {
        lenses.filter { $0.position == cameraPosition }
    }

    var hasFrontCamera: Bool { lenses.contains { $0.position == .front } }

    var canFlipCamera: Bool {
        hasFrontCamera && !isDualActive && !isAwaitingSecondFrame
    }

    var isDualActive: Bool { pipeline == .dual }

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
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    private var photoRotationAngle: CGFloat {
        guard let lens = selectedLens, FrontCameraPipeline.isCenterStage(lens) else {
            return reference.captureAngle
        }
        return FrontCameraPipeline.photoRotationAngle(reference: reference.captureAngle)
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
        pendingLensID = lens.id
        await serialized { await self.performSelect(lens) }
        if pendingLensID == lens.id { pendingLensID = nil }
    }

    func requestLens(_ lens: Lens) {
        pendingLensID = lens.id
        Task { await select(lens) }
    }

    func setMode(_ mode: CaptureMode) async {
        await serialized { await self.performSetMode(mode) }
    }

    func capture() async {
        await serialized { await self.performCapture() }
    }

    func toggleDual() async {
        await serialized { await self.performSetDual(!self.isDualActive) }
    }

    func flipCamera() async {
        guard canFlipCamera else { return }

        let target: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        guard let lens = lastLens[target] ?? Self.defaultLens(in: lenses, at: target) else { return }

        await select(lens)
    }

    func updateDualLayout(_ style: DualLayoutStyle) {
        let previous = dualLayout
        dualLayout = style
        guard isDualActive, previous == .pictureInPicture, style == .split else { return }
        Task { await serialized { await self.refreshDual() } }
    }

    func cancelDoubleExposureSequence() {
        guard isAwaitingSecondFrame else { return }
        exposureSequence = .none
        emit(.failure)
        Task { await serialized { await self.discardHeldExposure() } }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    func setGeotagging(_ enabled: Bool) {
        if enabled {
            guard !LocationProvider.isDenied else {
                emit(.failure)
                show(.locationDenied)
                return
            }
            settings.geotagsPhotos = true
            location.start()
        } else {
            settings.geotagsPhotos = false
            location.stop()
        }
    }

    func geotagAccessDenied() {
        guard settings.geotagsPhotos else { return }
        settings.geotagsPhotos = false
        location.stop()
        emit(.failure)
        show(.locationDenied)
    }

    private func resumeGeotagging() {
        guard settings.geotagsPhotos else { return }
        if LocationProvider.isDenied {
            settings.geotagsPhotos = false
        } else if LocationProvider.isAuthorized {
            location.start()
        }
    }

    func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        emit(.tap)
        UIApplication.shared.open(url)
    }

    private func emit(_ kind: FeedbackEvent.Kind) {
        feedback = FeedbackEvent(serial: feedback.serial + 1, kind: kind)
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

    private func show(_ notice: Notice) {
        noticeTask?.cancel()
        self.notice = notice
        guard notice.dismissesAutomatically else { return }

        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }

    private func performStart() async {
        guard phase != .running else { return }

        if lenses.isEmpty {
            lenses = LensCatalog.lenses()
            isDualAvailable = AVCaptureMultiCamSession.isMultiCamSupported
                && Self.dualPair(in: lenses) != nil
        }

        #if targetEnvironment(simulator)
        if lenses.isEmpty {
            Log.capture.warning("No lenses discovered — proceeding in Simulator UI-preview mode")
            phase = .running
            return
        }
        #endif

        guard let rear = Self.defaultLens(in: lenses, at: .back) else {
            phase = .failed(CaptureError.noLensesAvailable.localizedDescription)
            return
        }

        let initial = selectedLens ?? rear
        apply(initial)
        reference.bind(to: rear)

        if isDualActive {
            _ = await enterDual()
        } else {
            do {
                try await engine.select(lens: initial)
                whiteBalance.bind(to: initial)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }

        if case .failed = phase { return }

        phase = .running
        recentPhoto.start()
        resumeGeotagging()

        Task { await renderer.warmUp() }
    }

    private func performStop() async {
        location.stop()
        await dualEngine.stop()
        await engine.stop()
        if phase == .running { phase = .idle }
    }

    private func performSelect(_ lens: Lens) async {
        guard pendingLensID == lens.id else { return }
        guard lens.id != selectedLens?.id, activity == .idle, !isDualActive else { return }
        activity = .switching
        defer { activity = .idle }

        emit(.lensSwitch)
        do {
            try await engine.select(lens: lens)
            apply(lens)
        } catch {
            emit(.failure)
            show(.lensSwitchFailed(lens.position == .front ? "front camera" : "\(lens.label) lens"))
            Log.lens.error("Lens switch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performSetMode(_ mode: CaptureMode) async {
        guard mode != selectedMode, activity == .idle, !isDualActive else { return }

        activity = .changingMode
        defer { activity = .idle }

        if isAwaitingSecondFrame, !mode.isDoubleExposure {
            exposureSequence = .none
            emit(.failure)
            await discardHeldExposure()
        }

        if mode.isDoubleExposure != selectedMode.isDoubleExposure {
            await applyExposureBias(mode.isDoubleExposure ? DoubleExposureProfile.exposureBias : nil)
        }

        selectedMode = mode
        emit(.selection)
    }

    private func performSetDual(_ enabled: Bool) async {
        guard enabled != isDualActive, activity == .idle else { return }
        guard !enabled || isDualAvailable else { return }

        activity = .switching
        defer { activity = .idle }

        if enabled {
            if isAwaitingSecondFrame {
                exposureSequence = .none
                emit(.failure)
                await discardHeldExposure()
            }
            _ = await enterDual()
        } else {
            await exitDual()
            if selectedMode.isDoubleExposure {
                await applyExposureBias(DoubleExposureProfile.exposureBias)
            }
        }
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
            try await dualEngine.start(rear: pair.rear, front: pair.front, style: dualLayout)
        } catch {
            Log.capture.error("Dual start failed: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
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

    private func refreshDual() async {
        guard isDualActive, activity == .idle else { return }
        activity = .switching
        defer { activity = .idle }
        _ = await enterDual()
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

    private func performCapture() async {
        guard phase == .running, activity == .idle, developingCount < developLimit else { return }
        activity = .capturing
        defer { activity = .idle }

        if isDualActive {
            await captureDual()
            return
        }

        let request = makeRequest()
        let isSecondExposure = isAwaitingSecondFrame

        if selectedMode.isDoubleExposure, !isSecondExposure {
            await captureFirstExposure(request)
            return
        }

        guard let shot = await takePhoto(request, errorContext: "Capture") else { return }

        if isSecondExposure {
            exposureSequence = .none
            await applyExposureBias(nil)
        }
        beginDevelop(shot, request: request, finishingDoubleExposure: isSecondExposure)
    }

    private var geotag: CLLocation? {
        settings.geotagsPhotos ? location.freshLocation : nil
    }

    private func makeRequest() -> CaptureRequest {
        CaptureRequest(
            id: UUID(),
            mode: selectedMode,
            position: cameraPosition,
            rotationAngle: photoRotationAngle,
            isPortrait: abs(sin(reference.captureAngle * .pi / 180)) > 0.5,
            flashMode: settings.flashMode,
            location: geotag
        )
    }

    private func captureDual() async {
        guard pipeline == .dual, let frames = await dualEngine.captureFrames() else {
            Log.capture.error("Dual capture failed: no frames available")
            emit(.failure)
            show(.captureFailed)
            return
        }

        fireShutterFeedback()

        let id = UUID()
        let rearOrientation = CGImagePropertyOrientation(rotationAngle: rotation.captureAngle)
        let frontOrientation = CGImagePropertyOrientation(rotationAngle: dualFrontAngle)
        let style = dualLayout
        let place = geotag

        developingCount += 1
        Task {
            await BackgroundTime.run("Onyx.developDual") {
                await developDual(
                    frames,
                    id: id,
                    rearOrientation: rearOrientation,
                    frontOrientation: frontOrientation,
                    style: style,
                    location: place
                )
            }
            developingCount -= 1
        }
    }

    private func captureFirstExposure(_ request: CaptureRequest) async {
        await applyExposureBias(DoubleExposureProfile.exposureBias)

        guard let shot = await takePhoto(request, errorContext: "First exposure") else {
            await applyExposureBias(nil)
            return
        }

        do {
            let previewData = try await renderer.beginDoubleExposure(shot, request: request)
            guard let preview = UIImage(data: previewData) else {
                throw CaptureError.renderFailed("Could not build ghost overlay preview")
            }
            exposureSequence = .awaitingSecond(ghost: preview)
            emit(.selection)
        } catch {
            Log.render.error("Double exposure hold failed [\(request.id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
            show(.captureFailed)
            await applyExposureBias(nil)
        }
    }

    private func takePhoto(_ request: CaptureRequest, errorContext: String) async -> RawCapture? {
        do {
            return try await engine.capturePhoto(
                request: request,
                onShutterFire: {
                    Task { @MainActor in self.fireShutterFeedback() }
                }
            )
        } catch {
            Log.capture.error("\(errorContext) failed [\(request.id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
            show(.captureFailed)
            return nil
        }
    }

    private func beginDevelop(_ shot: RawCapture, request: CaptureRequest, finishingDoubleExposure: Bool) {
        developingCount += 1
        Task {
            await BackgroundTime.run("Onyx.develop") {
                await develop(shot, request: request, finishingDoubleExposure: finishingDoubleExposure)
            }
            developingCount -= 1
        }
    }

    private func develop(_ shot: RawCapture, request: CaptureRequest, finishingDoubleExposure: Bool) async {
        do {
            let output = finishingDoubleExposure
                ? try await renderer.finishDoubleExposure(shot, request: request)
                : try await renderer.render(shot, request: request)

            try await library.save(heic: output.heic, location: request.location)
            emit(.success)

            if output.isDegraded { show(.effectUnavailable(request.mode.displayName)) }

            Log.render.info("Developed [\(request.id.uuidString, privacy: .public)] mode=\(request.mode.rawValue, privacy: .public) via \(output.usedRAWPath ? "RAW" : "ISP fallback") path, degraded=\(output.isDegraded)")
        } catch {
            Log.render.error("Develop failed [\(request.id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
            show(.saveFailed)
        }
    }

    private func developDual(
        _ frames: DualFrames,
        id: UUID,
        rearOrientation: CGImagePropertyOrientation,
        frontOrientation: CGImagePropertyOrientation,
        style: DualLayoutStyle,
        location: CLLocation?
    ) async {
        do {
            let output = try await renderer.renderDual(
                frames,
                rearOrientation: rearOrientation,
                frontOrientation: frontOrientation,
                style: style
            )
            try await library.save(heic: output.heic, location: location)
            emit(.success)
        } catch {
            Log.render.error("Dual develop failed [\(id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
            show(.saveFailed)
        }
    }

    private func discardHeldExposure() async {
        await renderer.cancelDoubleExposure()
        await applyExposureBias(nil)
    }

    private func applyExposureBias(_ bias: Float?) async {
        do {
            if let bias {
                try await engine.setExposureBias(bias)
            } else {
                try await engine.restoreExposureBias()
            }
        } catch {
            Log.capture.error("Exposure bias update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fireShutterFeedback() {
        emit(.shutterFire)
        withAnimation(.easeOut(duration: Metrics.Blink.inDuration)) { blinkOpacity = Metrics.Blink.opacity }
        withAnimation(.easeIn(duration: Metrics.Blink.outDuration).delay(Metrics.Blink.inDuration)) {
            blinkOpacity = 0
        }
    }
}
