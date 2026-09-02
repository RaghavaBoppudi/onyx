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
    private(set) var isCapturing = false
    private(set) var isDeveloping = false
    private(set) var isSwitching = false
    var blinkOpacity: Double = 0

    var isBusy: Bool { isCapturing || isDeveloping }

    let rotation = RotationTracker()
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

    private func closestToWide(in lenses: [Lens]) -> Lens? {
        lenses.min { abs($0.factor - 1.0) < abs($1.factor - 1.0) }
    }

    func capture() async {
        guard phase == .running, !isBusy else { return }
        isCapturing = true

        let shot: RawCapture
        do {
            shot = try await engine.capturePhoto(
                rotationAngle: rotation.captureAngle,
                flashMode: settings.flashMode,
                onShutterFire: {
                    Task { @MainActor [weak self] in self?.fireShutterFeedback() }
                }
            )
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
            isCapturing = false
            return
        }

        isCapturing = false
        await develop(shot)
    }

    private func develop(_ shot: RawCapture) async {
        isDeveloping = true
        defer { isDeveloping = false }

        do {
            let output = shot.isRAW
                ? try await renderer.renderRAW(dngData: shot.data, orientation: shot.orientation)
                : try await renderer.renderProcessed(imageData: shot.data, orientation: shot.orientation)

            try await library.save(heic: output.heic)
            Haptics.shared.fire(.success)

            Log.render.info("Developed via \(output.usedRAWPath ? "RAW" : "ISP fallback") path")
        } catch {
            Log.render.error("Develop failed: \(error.localizedDescription)")
            Haptics.shared.fire(.failure)
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
