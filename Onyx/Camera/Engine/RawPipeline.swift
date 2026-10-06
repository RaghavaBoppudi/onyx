import AVFoundation
import os
import Synchronization

nonisolated extension AVCaptureDevice {
    func withConfigurationLock(_ body: () throws -> Void) throws {
        do {
            try lockForConfiguration()
        } catch {
            throw CaptureError.configurationFailed(error.localizedDescription)
        }
        defer { unlockForConfiguration() }
        try body()
    }
}

nonisolated private final class ResumeOnce: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { isClaimed -> Bool in
            if isClaimed { return false }
            isClaimed = true
            return true
        }
    }
}

nonisolated enum BoundedCompletion {
    static func run(
        timeout: Duration,
        _ start: (@escaping @Sendable () -> Void) -> Void
    ) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce()
            start {
                if once.claim() { continuation.resume(returning: true) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.claim() { continuation.resume(returning: false) }
            }
        }
    }
}

nonisolated private final class ObservationToken: @unchecked Sendable {
    private let observation: NSKeyValueObservation

    init(_ observation: NSKeyValueObservation) {
        self.observation = observation
    }

    func cancel() {
        observation.invalidate()
    }
}

nonisolated extension NSObjectProtocol where Self: NSObject {
    func values<Value: Sendable>(of keyPath: KeyPath<Self, Value>) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observation = observe(keyPath, options: [.initial, .new]) { _, change in
                if let value = change.newValue { continuation.yield(value) }
            }
            let token = ObservationToken(observation)
            continuation.onTermination = { _ in token.cancel() }
        }
    }
}

nonisolated extension AsyncStream where Element: Equatable & Sendable {
    func waitFor(_ target: Element, timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await value in self where value == target { return } }
            group.addTask { try? await Task.sleep(for: timeout) }
            _ = await group.next()
            group.cancelAll()
        }
    }
}

nonisolated extension AVCaptureDevice.Format {
    var maxPhotoPixelCount: Int {
        supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
    }
}

nonisolated enum RawPipeline {

    static func configure(output: AVCapturePhotoOutput, device: AVCaptureDevice) {
        output.maxPhotoQualityPrioritization = .speed

        if output.isZeroShutterLagSupported { output.isZeroShutterLagEnabled = false }
        if output.isResponsiveCaptureSupported { output.isResponsiveCaptureEnabled = false }
        if output.isAutoDeferredPhotoDeliverySupported {
            output.isAutoDeferredPhotoDeliveryEnabled = false
        }
        if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = false }
        if output.isContentAwareDistortionCorrectionSupported {
            output.isContentAwareDistortionCorrectionEnabled = false
        }
        if output.isDepthDataDeliverySupported { output.isDepthDataDeliveryEnabled = false }
        if output.isPortraitEffectsMatteDeliverySupported {
            output.isPortraitEffectsMatteDeliveryEnabled = false
        }
        output.enabledSemanticSegmentationMatteTypes = []
        if output.isLivePhotoCaptureSupported { output.isLivePhotoCaptureEnabled = false }

        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            output.maxPhotoDimensions = largest
        }
    }

    static func configure(device: AVCaptureDevice, zoomFactor: CGFloat, exposureBias: Float) {
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
        }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
        if device.activeFormat.supportedColorSpaces.contains(CaptureConstants.colorSpace) {
            device.activeColorSpace = CaptureConstants.colorSpace
        }

        applyMetering(to: device, exposureBias: exposureBias)

        device.videoZoomFactor = clampedZoom(zoomFactor, for: device)
    }

    static func clampedZoom(_ factor: CGFloat, for device: AVCaptureDevice) -> CGFloat {
        min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
    }

    private static let meteringPoint = CGPoint(x: 0.5, y: 0.5)

    private static func applyMetering(to device: AVCaptureDevice, exposureBias: Float) {
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = meteringPoint
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = meteringPoint
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        let bias = min(max(exposureBias, device.minExposureTargetBias),
                       device.maxExposureTargetBias)
        device.setExposureTargetBias(bias, completionHandler: nil)

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    static func resolveBayerFormat(
        output: AVCapturePhotoOutput,
        device: AVCaptureDevice
    ) -> OSType? {

        if let format = bayer(in: output) { return format }

        Log.capture.info("No RAW on preset format for \(device.localizedName); probing formats")

        let candidates = device.formats
            .filter { !$0.supportedMaxPhotoDimensions.isEmpty }
            .sorted { lhs, rhs in
                let l = lhs.maxPhotoPixelCount
                let r = rhs.maxPhotoPixelCount
                if l != r { return l > r }
                return lhs.maxISO > rhs.maxISO
            }

        let originalFormat = device.activeFormat

        for format in candidates {
            guard (try? device.lockForConfiguration()) != nil else { continue }
            device.activeFormat = format
            device.unlockForConfiguration()

            if let found = bayer(in: output) {
                Log.capture.info("RAW available after format switch for \(device.localizedName)")
                return found
            }
        }

        if (try? device.lockForConfiguration()) != nil {
            device.activeFormat = originalFormat
            device.unlockForConfiguration()
        }
        return nil
    }

    private static func bayer(in output: AVCapturePhotoOutput) -> OSType? {
        output.availableRawPhotoPixelFormatTypes.first {
            AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
        }
    }

    static func makeSettings(
        output: AVCapturePhotoOutput,
        bayerFormat: OSType?,
        flashMode: AVCaptureDevice.FlashMode
    ) -> AVCapturePhotoSettings {

        let settings: AVCapturePhotoSettings

        if let raw = bayerFormat {
            settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
            settings.rawFileFormat = nil
        } else {
            settings = output.availablePhotoCodecTypes.contains(.hevc)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                : AVCapturePhotoSettings()
        }

        settings.photoQualityPrioritization = .speed
        settings.flashMode = output.supportedFlashModes.contains(flashMode) ? flashMode : .off
        settings.isAutoRedEyeReductionEnabled = false
        settings.isDepthDataDeliveryEnabled = false
        settings.isPortraitEffectsMatteDeliveryEnabled = false
        settings.enabledSemanticSegmentationMatteTypes = []
        settings.isAutoVirtualDeviceFusionEnabled = false
        settings.isAutoContentAwareDistortionCorrectionEnabled = false
        settings.maxPhotoDimensions = output.maxPhotoDimensions

        return settings
    }
}
