//  CameraModel.swift
//  The only bridge between SwiftUI and the capture/render actors.
//
//  Capture is three hops: shoot (actor), develop (actor), save (actor). The shutter
//  frees itself the moment the exposure lands; developing continues in the
//  background so the user can keep shooting.
//
//  The corner thumbnail is no longer state this class manages. It used to be: set
//  `lastCapture` from whatever `develop()` produced, in whatever order renders
//  happened to finish. Two shots fired close together could develop out of order —
//  now that rendering is CPU-bound and variable-latency, that was a live
//  correctness gap, not a hypothetical one. `RecentPhotoWatcher` replaces it with a
//  live fetch of the library's actual most-recent photo, which can't be shown out
//  of order because it isn't a value this class sets — it's a value PhotoKit
//  reports. `CameraModel` doesn't hand it anything after a save; the new asset
//  becomes the most recent one automatically, and the watcher's own change
//  notification picks it up on its own.

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

    /// True while either a capture or a develop is in flight. Drives the shutter's
    /// enabled state — bounds how many shots can queue up waiting on the render
    /// pipeline to one, rather than letting rapid taps pile up raw capture bytes
    /// faster than an older device can process them.
    var isBusy: Bool { isCapturing || isDeveloping }
    private(set) var isSwitching = false
    var blinkOpacity: Double = 0

    let rotation = RotationTracker()
    let recentPhoto = RecentPhotoWatcher()

    var sessionBox: CaptureSessionBox { engine.box }

    private let engine = CaptureEngine()
    private let renderer = ImageRenderer()
    private let library = PhotoLibraryWriter()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Lifecycle

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
            // Both off the critical path — neither blocks the viewfinder appearing.
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

    // MARK: - Lens control

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

    // MARK: - Capture

    func capture() async {
        guard phase == .running, !isBusy else { return }
        isCapturing = true

        let shot: RawCapture
        do {
            shot = try await engine.capturePhoto(
                rotationAngle: rotation.captureAngle,
                flashMode: settings.flashMode,
                onShutterFire: { [weak self] in
                    Task { @MainActor in self?.fireShutterFeedback() }
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
            // No further action needed for the thumbnail — the save above makes
            // this the library's newest asset, and RecentPhotoWatcher's own
            // PHPhotoLibraryChangeObserver notification picks it up on its own.
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

    /// Photos exposes no public API for deep-linking to a specific asset.
    func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        Haptics.shared.fire(.toggle)
        UIApplication.shared.open(url)
    }
}
