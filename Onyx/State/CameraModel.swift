import AVFoundation
import SwiftUI

@MainActor
@Observable
final class CameraModel {

    enum Phase: Equatable {
        case idle, requestingAccess, denied, running, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lenses: [Lens] = []
    private(set) var selectedLens: Lens?
    private(set) var isBusy = false
    private(set) var isSwitching = false
    private(set) var selectedLook: LookKind = .standard
    private(set) var ghostOverlay: UIImage?
    private(set) var blinkOpacity: Double = 0

    let rotation = RotationTracker()
    let whiteBalance = WhiteBalanceReadiness()
    let recentPhoto = RecentPhotoWatcher()
    let location = LocationProvider()

    var isAwaitingSecondFrame: Bool { ghostOverlay != nil }

    var isOnDimmerLens: Bool {
        guard let lens = selectedLens else { return false }
        return abs(lens.factor - 1.0) >= 0.01
    }

    var sessionBox: CaptureSessionBox { engine.box }

    private let engine = CaptureEngine()
    private let renderer = ImageRenderer()
    private let library = PhotoLibraryWriter()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() async {
        guard phase != .running else { return }
        phase = .requestingAccess

        guard await engine.requestCameraAccess() else {
            phase = .denied
            return
        }

        lenses = LensCatalog.lenses()

        #if targetEnvironment(simulator)
        if lenses.isEmpty {
            Log.capture.warning("No lenses discovered — proceeding in Simulator UI-preview mode")
            phase = .running
            return
        }
        #endif

        guard let initial = lenses.min(by: { abs($0.factor - 1.0) < abs($1.factor - 1.0) }) else {
            phase = .failed(CaptureError.noLensesAvailable.localizedDescription)
            return
        }

        do {
            try await engine.select(lens: initial)
            apply(initial)
            whiteBalance.bind(to: initial)
            phase = .running
            Haptics.shared.prepare()
            location.start()
            Task { await renderer.warmUp() }
            Task { await recentPhoto.start() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        location.stop()
        await engine.stop()
        if phase == .running { phase = .idle }
    }

    func select(_ lens: Lens) async {
        guard lens.id != selectedLens?.id, !isSwitching else { return }
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

    private func apply(_ lens: Lens) {
        selectedLens = lens
        rotation.bind(to: lens)
    }

    func setLook(_ look: LookKind) {
        guard look != selectedLook else { return }

        if isAwaitingSecondFrame, !look.isDoubleExposure {
            cancelDoubleExposureSequence()
        }

        if look.isDoubleExposure != selectedLook.isDoubleExposure {
            let bias = look.isDoubleExposure ? DoubleExposureProfile.exposureBias : CaptureConstants.exposureBias
            Task { try? await engine.setExposureBias(bias) }
        }

        selectedLook = look
    }

    func cancelDoubleExposureSequence() {
        guard isAwaitingSecondFrame else { return }
        ghostOverlay = nil
        Task {
            await renderer.cancelDoubleExposure()
            try? await engine.setExposureBias(CaptureConstants.exposureBias)
        }
        Haptics.shared.fire(.failure)
    }

    func capture() async {
        guard phase == .running, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        if selectedLook.isDoubleExposure, !isAwaitingSecondFrame {
            await captureFirstExposure()
        } else if let shot = await takePhoto(errorContext: "Capture") {
            await develop(shot)
        }
    }

    private func captureFirstExposure() async {
        try? await engine.setExposureBias(DoubleExposureProfile.exposureBias)

        guard let shot = await takePhoto(errorContext: "First exposure") else {
            try? await engine.setExposureBias(CaptureConstants.exposureBias)
            return
        }

        do {
            let previewData = try await renderer.beginDoubleExposure(shot, look: selectedLook)
            guard let preview = UIImage(data: previewData) else {
                throw CaptureError.renderFailed("Could not build ghost overlay preview")
            }
            ghostOverlay = preview
            Haptics.shared.fire(.selection)
        } catch {
            Log.render.error("Double exposure hold failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            try? await engine.setExposureBias(CaptureConstants.exposureBias)
        }
    }

    private func takePhoto(errorContext: String) async -> RawCapture? {
        do {
            return try await engine.capturePhoto(
                rotationAngle: rotation.captureAngle,
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

        do {
            let output = wasFinishingDoubleExposure
                ? try await renderer.finishDoubleExposure(shot, look: selectedLook)
                : try await renderer.render(shot, look: selectedLook)
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
            try? await engine.setExposureBias(CaptureConstants.exposureBias)
        }
    }

    private func fireShutterFeedback() {
        Haptics.shared.fire(.shutterFire)
        withAnimation(Metrics.Motion.blinkIn) { blinkOpacity = Metrics.Blink.opacity }
        withAnimation(Metrics.Motion.blinkOut.delay(Metrics.Blink.inDuration)) {
            blinkOpacity = 0
        }
    }

    func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        Haptics.shared.fire(.toggle)
        UIApplication.shared.open(url)
    }
}
