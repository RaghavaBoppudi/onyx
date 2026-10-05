import AVFoundation
import os

nonisolated enum FrontCameraPipeline {

    static let mirrorsSavedImage = false

    private static let fallbackNarrowFieldOfView: CGFloat = 70
    private static let photoAngleOffset: CGFloat = -90
    private static let dualAngleOffset: CGFloat = 90

    static func isCenterStage(_ lens: Lens) -> Bool {
        lens.position == .front && lens.deviceType == .builtInUltraWideCamera
    }

    static func photoRotationAngle(reference: CGFloat) -> CGFloat {
        normalized(reference + photoAngleOffset)
    }

    static func dualRotationAngle(device: CGFloat) -> CGFloat {
        normalized(device + dualAngleOffset)
    }

    static func selectFormat(on device: AVCaptureDevice) throws {
        guard device.deviceType == .builtInUltraWideCamera else { return }

        let portraitCapable = device.formats.filter {
            $0.supportedDynamicAspectRatios.contains(.ratio3x4)
        }
        let smartFraming = portraitCapable.filter(\.isSmartFramingSupported)
        let pool = smartFraming.isEmpty ? portraitCapable : smartFraming

        guard let format = pool.max(by: { $0.maxPhotoPixelCount < $1.maxPhotoPixelCount }) else {
            Log.capture.warning("Front camera: no format supports a 3:4 dynamic aspect ratio")
            return
        }

        try device.withConfigurationLock {
            device.activeFormat = format
        }

        let dimensions = format.formatDescription.dimensions
        Log.capture.info("Front camera format \(dimensions.width)x\(dimensions.height), smart framing \(format.isSmartFramingSupported)")
    }

    static func zoomFactor(for lens: Lens, on device: AVCaptureDevice) -> CGFloat {
        guard lens.position == .front, device.deviceType == .builtInUltraWideCamera else {
            return lens.deviceZoomFactor
        }

        if lens.factor <= CenterStageProfile.wideFactor {
            return device.minAvailableVideoZoomFactor
        }

        return RawPipeline.clampedZoom(narrowZoomFactor(on: device), for: device)
    }

    static func applyPortraitAspectRatio(to device: AVCaptureDevice) async throws {
        guard device.activeFormat.supportedDynamicAspectRatios.contains(.ratio3x4) else {
            Log.capture.warning("Front camera: active format has no 3:4 dynamic aspect ratio")
            return
        }
        guard device.dynamicAspectRatio != .ratio3x4 else { return }

        do {
            try device.lockForConfiguration()
        } catch {
            throw CaptureError.configurationFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }

        let completed = await BoundedCompletion.run(timeout: .seconds(2)) { finish in
            device.setDynamicAspectRatio(.ratio3x4) { _, error in
                if let error {
                    Log.capture.warning("Front camera: dynamic aspect ratio failed: \(error.localizedDescription, privacy: .public)")
                }
                finish()
            }
        }

        if completed {
            Log.capture.info("Front camera dynamic aspect ratio set to 3:4")
        } else {
            Log.capture.warning("Front camera: dynamic aspect ratio change timed out")
        }
    }

    private static func normalized(_ angle: CGFloat) -> CGFloat {
        (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func narrowZoomFactor(on device: AVCaptureDevice) -> CGFloat {
        let framings = device.smartFramingMonitor?.supportedFramings ?? []
        let portrait = framings.filter { $0.aspectRatio == .ratio3x4 }
        let candidates = (portrait.isEmpty ? framings : portrait).map { CGFloat($0.zoomFactor) }

        if let narrowest = candidates.max(), narrowest > device.minAvailableVideoZoomFactor {
            return narrowest
        }
        return fieldOfViewZoom(for: device)
    }

    private static func fieldOfViewZoom(for device: AVCaptureDevice) -> CGFloat {
        let wide = CGFloat(device.activeFormat.videoFieldOfView)
        guard wide > fallbackNarrowFieldOfView else { return device.minAvailableVideoZoomFactor }
        return tan(wide * .pi / 360) / tan(fallbackNarrowFieldOfView * .pi / 360)
    }
}
