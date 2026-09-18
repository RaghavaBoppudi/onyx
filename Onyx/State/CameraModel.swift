import AVFoundation
import SwiftUI

@MainActor
@Observable
final class CameraModel {

    enum Phase: Equatable {
        case idle, requestingAccess, denied, running, failed(String)
    }

    enum ExposureStage {
        case idle
        case awaitingSecondFrame(ghostOverlay: UIImage)
    }

    private(set) var phase: Phase = .idle
    private(set) var lenses: [Lens] = []
    private(set) var selectedLens: Lens?
    private(set) var isCapturing = false
    private(set) var isDeveloping = false
    private(set) var isSwitching = false
    private(set) var selectedLook: LookKind = .standard
    private(set) var exposureStage: ExposureStage = .idle
    var blinkOpacity: Double = 0

    var isBusy: Bool { isCapturing || isDeveloping }

    var isAwaitingSecondFrame: Bool {
        if case .awaitingSecondFrame = exposureStage { true } else { false }
    }

    let rotation = RotationTracker()
    let whiteBalance = WhiteBalanceReadiness()
    let recentPhoto = RecentPhotoWatcher()

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

        guard let initial = closestToWide(in: lenses) else {
            phase = .failed(CaptureError.noLensesAvailable.localizedDescription)
            return
        }

        do {
            try await engine.start(with: initial)
            apply(initial)
            whiteBalance.bind(to: initial)
            phase = .running
            Haptics.shared.prepare()
            Task { await renderer.warmUp() }
            Task { await recentPhoto.start() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func stop() async {
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
            Task {
                await renderer.cancelDoubleExposure()
                try? await engine.setExposureBias(CaptureConstants.exposureBias)
            }
            exposureStage = .idle
        }

        if look.isDoubleExposure, !selectedLook.isDoubleExposure {
            Task { try? await engine.setExposureBias(DoubleExposureProfile.exposureBias) }
        } else if !look.isDoubleExposure, selectedLook.isDoubleExposure {
            Task { try? await engine.setExposureBias(CaptureConstants.exposureBias) }
        }

        Haptics.shared.fire(.selection)
        selectedLook = look
    }

    private func closestToWide(in lenses: [Lens]) -> Lens? {
        lenses.min { abs($0.factor - 1.0) < abs($1.factor - 1.0) }
    }

    func capture() async {
        guard phase == .running, !isBusy else { return }

        if selectedLook.isDoubleExposure, !isAwaitingSecondFrame {
            await captureFirstExposure()
        } else {
            await captureAndDevelop()
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
            exposureStage = .awaitingSecondFrame(ghostOverlay: preview)
            Haptics.shared.fire(.selection)
        } catch {
            Log.render.error("Double exposure hold failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            try? await engine.setExposureBias(CaptureConstants.exposureBias)
        }
    }

    private func captureAndDevelop() async {
        guard let shot = await takePhoto(errorContext: "Capture") else { return }
        await develop(shot)
    }

    private func takePhoto(errorContext: String) async -> RawCapture? {
        isCapturing = true
        defer { isCapturing = false }

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
        isDeveloping = true
        defer { isDeveloping = false }

        let wasFinishingDoubleExposure = isAwaitingSecondFrame

        do {
            let output: ImageRenderer.Output
            if wasFinishingDoubleExposure {
                output = try await renderer.finishDoubleExposure(shot, look: selectedLook)
                exposureStage = .idle
            } else {
                output = shot.isRAW
                    ? try await renderer.renderRAW(dngData: shot.data, orientation: shot.orientation, look: selectedLook)
                    : try await renderer.renderProcessed(imageData: shot.data, orientation: shot.orientation, look: selectedLook)
            }

            try await library.save(heic: output.heic)
            Haptics.shared.fire(.success)

            Log.render.info("Developed via \(output.usedRAWPath ? "RAW" : "ISP fallback") path")
        } catch {
            Log.render.error("Develop failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            exposureStage = .idle
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
