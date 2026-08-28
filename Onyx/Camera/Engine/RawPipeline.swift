//  RawPipeline.swift
//  Configures the session so the capture is a single, unfused exposure.
//
//  `photoQualityPrioritization = .speed` is the load-bearing line. With `.quality`
//  or `.balanced` the system runs Fusion-style processing across multiple exposures
//  and overrides manual controls entirely. Everything else here is switching off
//  optional ISP stages one at a time.
//
//  This is about the *computational* layer, not the ISP itself. The ISP still
//  demosaics — that is unavoidable, and it is why the RAW path exists: CIRAWFilter
//  lets us do that step ourselves with Apple's tone curve disabled.
//
//  Metering — focus, exposure and white balance — lives here rather than in its own
//  file. It was split out once; the split never earned itself, because it was only
//  ever called from one place, immediately, as part of the same device
//  configuration this file already owns. Centre-weighted metering with the point of
//  interest at the frame centre is what "focus on the middle, meter for the whole
//  shot" means in AVFoundation terms, and applying it identically on every lens is
//  what keeps 0.5x, 1x and 2x/4x from reading as differently-behaved cameras.

import AVFoundation

enum RawPipeline {

    // MARK: - Output

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

    // MARK: - Device

    /// No zoom parameter: rear lenses are always at 1.0. We switch glass rather than
    /// crop, because a crop never reaches the RAW readout anyway.
    static func configure(device: AVCaptureDevice) {
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

        applyMetering(to: device)

        device.videoZoomFactor = max(1.0, device.minAvailableVideoZoomFactor)
    }

    /// Centre of the frame in AVFoundation's normalised coordinate space.
    private static let meteringPoint = CGPoint(x: 0.5, y: 0.5)

    private static func applyMetering(to device: AVCaptureDevice) {
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

        let bias = min(max(CaptureConstants.exposureBias, device.minExposureTargetBias),
                       device.maxExposureTargetBias)
        device.setExposureTargetBias(bias, completionHandler: nil)

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }

    // MARK: - RAW availability

    /// `availableRawPhotoPixelFormatTypes` is a property of the *active format*, not
    /// of the device. A device can support RAW on one format and not another, and
    /// the `.photo` preset does not always land on a RAW-capable one — which is why
    /// the iPhone 11 Pro ultra-wide reported no Bayer format.
    ///
    /// Probes `device.formats` largest-first and switches `activeFormat` if that
    /// finds RAW, restoring the preset's choice if nothing does. Checked explicitly
    /// for Bayer, since the list can also contain Apple ProRAW formats.
    ///
    /// This is genuinely expensive — locking configuration and checking each
    /// candidate format in turn — which is why `CaptureEngine` caches the result
    /// per lens rather than calling this on every switch back to a lens it has
    /// already probed.
    static func resolveBayerFormat(
        output: AVCapturePhotoOutput,
        device: AVCaptureDevice
    ) -> OSType? {

        if let format = bayer(in: output) { return format }

        Log.capture.info("No RAW on preset format for \(device.localizedName); probing formats")

        let candidates = device.formats
            .filter { !$0.supportedMaxPhotoDimensions.isEmpty }
            .sorted { lhs, rhs in
                let l = lhs.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
                let r = rhs.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
                return l > r
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

    // MARK: - Per-shot settings

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
        // Not every lens supports flash the same way — checked rather than assumed,
        // failing to .off if the current optic doesn't list this mode as supported.
        // The same "no surprises" principle that dropped auto-flash applies to
        // hardware capability too: never let the app request something the lens
        // can't actually honour and hope AVFoundation quietly does the right thing.
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
