import AVFoundation
import CoreLocation
import SwiftUI
import os

enum Notice: Equatable {
    case libraryDenied
    case saveFailed
    case captureFailed
    case lensSwitchFailed(String)
    case effectUnavailable(String)
    case locationDenied
    case rawUnavailable
    case ledgerFailed
    case locationUnavailable

    var message: String {
        switch self {
        case .libraryDenied: "Allow Photos access in Settings so Onyx can save your shots."
        case .saveFailed: "That photo couldn't be saved."
        case .captureFailed: "That photo couldn't be taken."
        case .lensSwitchFailed(let target): "Couldn't switch to the \(target)."
        case .effectUnavailable(let mode): "\(mode) couldn't be applied to that photo."
        case .locationDenied: "Allow Location access in Settings to geotag your photos."
        case .rawUnavailable: "This lens can't shoot RAW, so Journalist mode can't use it."
        case .ledgerFailed: "Saved, but the capture log couldn't be updated."
        case .locationUnavailable: "Saved without location. No recent GPS fix was available."
        }
    }

    var showsSettings: Bool { self == .libraryDenied || self == .locationDenied }
    var dismissesAutomatically: Bool { !showsSettings }
}

@MainActor
@Observable
final class CameraModel {

    enum Phase: Equatable {
        case idle, requestingAccess, denied, running, failed(String)
    }

    enum Pipeline: Equatable {
        case single, dual
    }

    enum Activity: Equatable {
        case idle, switching, capturing
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
    private(set) var profile: CaptureProfile = .standard
    private(set) var pendingProfile: CaptureProfile?
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

    private var developLimit: Int { isJournalist ? 2 : 3 }

    var isJournalist: Bool { profile == .journalist }

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

    var canChangeProfile: Bool {
        phase == .running && activity == .idle && pendingProfile == nil
    }

    var ghostOverlay: UIImage? {
        if case .awaitingSecond(let ghost) = exposureSequence { ghost } else { nil }
    }

    var isAwaitingSecondFrame: Bool { ghostOverlay != nil }

    var cameraPosition: AVCaptureDevice.Position { selectedLens?.position ?? .back }

    var visibleLenses: [Lens] {
        let position: AVCaptureDevice.Position = isJournalist ? .back : cameraPosition
        return lenses.filter { $0.position == position }
    }

    var hasFrontCamera: Bool { lenses.contains { $0.position == .front } }

    var canFlipCamera: Bool {
        hasFrontCamera && !isDualActive && !isAwaitingSecondFrame && !isJournalist
    }

    var isDualActive: Bool { pipeline == .dual }

    var availableModes: [CaptureMode] { CaptureMode.allCases }

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
    private let ledger = CaptureLedger()
    private let settings: AppSettings
    private var lastLens: [AVCaptureDevice.Position: Lens] = [:]

    @ObservationIgnored private var lastOperation: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var hasLibraryAccess = false

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
        self.profile = settings.captureProfile
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

    func requestProfile(_ new: CaptureProfile) {
        guard canChangeProfile, new != profile else { return }
        pendingProfile = new
        Task { await serialized { await self.performSetProfile(new) } }
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

        if pipeline == .dual {
            _ = await enterDual()
        } else {
            do {
                try await engine.select(lens: initial)
                pipeline = .single
                whiteBalance.bind(to: initial)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }

        if case .failed = phase { return }

        phase = .running

        hasLibraryAccess = PhotosAuthorization.hasReadWriteAccess
        if hasLibraryAccess { await recentPhoto.start() }

        if isJournalist {
            await applyExposureBias(CaptureConstants.journalistExposureBias)
            if settings.geotagsPhotos, LocationProvider.isAuthorized { location.start() }
        }

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
        guard mode != selectedMode, activity == .idle, !isDualActive, !isJournalist else { return }

        activity = .switching
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

    private func performSetProfile(_ new: CaptureProfile) async {
        defer { if pendingProfile == new { pendingProfile = nil } }
        guard pendingProfile == new, new != profile else { return }

        activity = .switching
        defer { activity = .idle }

        if new == .journalist {
            if isAwaitingSecondFrame {
                exposureSequence = .none
                await discardHeldExposure()
            }
            if isDualActive { await exitDual() }
            if cameraPosition == .front { await returnToRearLens() }

            await applyExposureBias(CaptureConstants.journalistExposureBias)
            profile = .journalist
            if settings.geotagsPhotos, LocationProvider.isAuthorized { location.start() }
        } else {
            location.stop()
            await applyExposureBias(selectedMode.isDoubleExposure ? DoubleExposureProfile.exposureBias : nil)
            profile = .standard
        }

        settings.captureProfile = new
        emit(.selection)
    }

    private func returnToRearLens() async {
        guard let rear = lastLens[.back] ?? Self.defaultLens(in: lenses, at: .back) else { return }

        do {
            try await engine.select(lens: rear)
            apply(rear)
        } catch {
            emit(.failure)
            show(.lensSwitchFailed("\(rear.label) lens"))
            Log.lens.error("Return to rear lens failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performSetDual(_ enabled: Bool) async {
        guard enabled != isDualActive, activity == .idle else { return }
        guard !enabled || (isDualAvailable && !isJournalist) else { return }

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

        guard await ensureLibraryAccess() else { return }

        if isJournalist {
            await captureJournalist()
            return
        }

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

    private func makeRequest() -> CaptureRequest {
        CaptureRequest(
            id: UUID(),
            mode: selectedMode,
            position: cameraPosition,
            rotationAngle: photoRotationAngle,
            isPortrait: abs(sin(reference.captureAngle * .pi / 180)) > 0.5,
            flashMode: settings.flashMode,
            location: isJournalist && settings.geotagsPhotos ? location.freshLocation : nil
        )
    }

    private func ensureLibraryAccess() async -> Bool {
        if hasLibraryAccess { return true }

        guard await PhotosAuthorization.requestReadWrite() else {
            emit(.failure)
            show(.libraryDenied)
            return false
        }

        hasLibraryAccess = true
        if notice == .libraryDenied { dismissNotice() }
        await recentPhoto.start()
        return true
    }

    private func captureJournalist() async {
        if settings.geotagsPhotos, !location.isRunning, LocationProvider.isAuthorized {
            location.start()
        }

        let request = makeRequest()

        guard let shot = await takePhoto(request, errorContext: "Journalist capture") else { return }

        guard shot.isRAW else {
            Log.capture.error("Journalist capture returned processed data on \(self.selectedLens?.label ?? "unknown", privacy: .public)")
            emit(.failure)
            show(.rawUnavailable)
            return
        }

        let wantsLocation = settings.geotagsPhotos
        let locationMissing = wantsLocation && request.location == nil

        let context = CaptureContext(
            id: request.id,
            capturedAtMillis: Int64(Date.now.timeIntervalSince1970 * 1000),
            lens: selectedLens?.label ?? "unknown",
            flashRequested: Self.flashLabel(request.flashMode),
            flashEnabled: shot.flashEnabled,
            exposureBiasRequested: CaptureConstants.journalistExposureBias,
            exposureBiasActual: shot.exposureBias,
            locationStatus: !wantsLocation ? "off" : (locationMissing ? "unavailable" : "recorded"),
            location: request.location.map { LocationEvidence($0) }
        )

        let entry = ledger.submit(dng: shot.data, context: context)

        developingCount += 1
        Task {
            await BackgroundTime.run("Onyx.saveDNG") {
                await saveDNG(shot.data, request: request, entry: entry, locationMissing: locationMissing)
            }
            developingCount -= 1
        }
    }

    private func saveDNG(
        _ data: Data,
        request: CaptureRequest,
        entry: Task<LedgerReceipt, any Error>,
        locationMissing: Bool
    ) async {
        var saveError: (any Error)?

        do {
            try await library.saveDNG(
                data,
                fileName: "Onyx-\(request.id.uuidString).dng",
                location: request.location
            )
            emit(.success)
        } catch {
            saveError = error
            Log.library.error("DNG save failed [\(request.id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            emit(.failure)
            show(.saveFailed)
        }

        do {
            let receipt = try await entry.value
            Log.library.info("Ledger #\(receipt.sequence) sha256 \(String(receipt.dngSHA256?.prefix(12) ?? ""), privacy: .public)")

            if let saveError {
                _ = ledger.submitStatus(
                    captureID: request.id,
                    event: "save-failed",
                    detail: saveError.localizedDescription
                )
            } else if locationMissing {
                show(.locationUnavailable)
            }
        } catch {
            Log.library.error("Ledger append failed [\(request.id.uuidString, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            if saveError == nil { show(.ledgerFailed) }
        }
    }

    private static func flashLabel(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .on: "on"
        case .auto: "auto"
        default: "off"
        }
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

        developingCount += 1
        Task {
            await BackgroundTime.run("Onyx.developDual") {
                await developDual(
                    frames,
                    id: id,
                    rearOrientation: rearOrientation,
                    frontOrientation: frontOrientation,
                    style: style
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
        style: DualLayoutStyle
    ) async {
        do {
            let output = try await renderer.renderDual(
                frames,
                rearOrientation: rearOrientation,
                frontOrientation: frontOrientation,
                style: style
            )
            try await library.save(heic: output.heic, location: nil)
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
