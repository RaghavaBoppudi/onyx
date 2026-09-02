import AVFoundation

enum RawPipeline {

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
