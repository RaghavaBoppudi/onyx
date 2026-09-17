import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

actor ImageRenderer {

    struct Output: @unchecked Sendable {
        let heic: Data
        let usedRAWPath: Bool
    }

    private let context: CIContext
    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let channelCurves: Data
    private let monoLuminanceCurve: Data

    init() {
        context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        let toneCurvePoints = [
            LookProfile.Curve.p0, LookProfile.Curve.p1, LookProfile.Curve.p2,
            LookProfile.Curve.p3, LookProfile.Curve.p4
        ]

        channelCurves = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: toneCurvePoints,
            red: LookProfile.ChannelResponse.red,
            green: LookProfile.ChannelResponse.green,
            blue: LookProfile.ChannelResponse.blue,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )

        monoLuminanceCurve = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: toneCurvePoints,
            red: MonochromeProfile.identityCurve,
            green: MonochromeProfile.identityCurve,
            blue: MonochromeProfile.identityCurve,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )
    }

    func warmUp() {
        let synthetic = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = try? encode(applyLook(to: synthetic), usedRAWPath: false)
        _ = try? encode(applyMonochrome(to: synthetic), usedRAWPath: false)
    }

    func renderRAW(
        dngData: Data,
        orientation: CGImagePropertyOrientation,
        look: LookKind
    ) throws -> Output {
        guard let filter = CIRAWFilter(imageData: dngData, identifierHint: nil) else {
            throw CaptureError.renderFailed("Could not open RAW data")
        }

        filter.boostAmount = LookProfile.Decode.boostAmount
        filter.boostShadowAmount = LookProfile.Decode.boostShadowAmount
        filter.localToneMapAmount = LookProfile.Decode.localToneMapAmount
        filter.extendedDynamicRangeAmount = LookProfile.Decode.extendedDynamicRangeAmount
        filter.baselineExposure = LookProfile.Decode.baselineExposure
        filter.luminanceNoiseReductionAmount = LookProfile.Decode.luminanceNoiseReduction
        filter.colorNoiseReductionAmount = LookProfile.Decode.colorNoiseReduction
        filter.sharpnessAmount = LookProfile.Decode.sharpness
        filter.detailAmount = LookProfile.Decode.detail
        filter.contrastAmount = LookProfile.Decode.contrast
        filter.orientation = orientation

        guard let decoded = filter.outputImage else {
            throw CaptureError.renderFailed("RAW decode produced no image")
        }

        Log.render.debug("RAW path, orientation \(orientation.rawValue), look \(look.rawValue)")
        let graded = look == .mono ? applyMonochrome(to: decoded) : applyLook(to: decoded)
        return try encode(graded, usedRAWPath: true)
    }

    func renderProcessed(
        imageData: Data,
        orientation: CGImagePropertyOrientation,
        look: LookKind
    ) throws -> Output {
        guard let source = CIImage(
            data: imageData,
            options: [.applyOrientationProperty: true]
        ) else {
            throw CaptureError.renderFailed("Could not open processed image data")
        }

        let embedded = (source.properties[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
        Log.render.debug(
            "ISP fallback path, embedded orientation \(embedded), capture angle implied \(orientation.rawValue), look \(look.rawValue)"
        )

        let graded = look == .mono ? applyMonochrome(to: source) : applyLook(to: source)
        return try encode(graded, usedRAWPath: false)
    }

    private func applyLook(to image: CIImage) -> CIImage {
        var result = image.applyingFilter("CILinearToSRGBToneCurve")

        let curves = CIFilter.colorCurves()
        curves.inputImage = result
        curves.curvesData = channelCurves
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.colorSpace = outputSpace
        result = curves.outputImage ?? result

        let controls = CIFilter.colorControls()
        controls.inputImage = result
        controls.saturation = LookProfile.Color.saturation
        controls.contrast = LookProfile.Color.contrast
        controls.brightness = LookProfile.Color.brightness
        result = controls.outputImage ?? result

        return result.applyingFilter("CISRGBToneCurveToLinear")
    }

    private func applyMonochrome(to image: CIImage) -> CIImage {
        var result = image.applyingFilter("CILinearToSRGBToneCurve")

        let mono = CIFilter.colorMatrix()
        mono.inputImage = result
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        mono.rVector = luma
        mono.gVector = luma
        mono.bVector = luma
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        result = mono.outputImage ?? result

        let curves = CIFilter.colorCurves()
        curves.inputImage = result
        curves.curvesData = monoLuminanceCurve
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.colorSpace = outputSpace
        result = curves.outputImage ?? result

        let controls = CIFilter.colorControls()
        controls.inputImage = result
        controls.saturation = 0
        controls.contrast = MonochromeProfile.Color.contrast
        controls.brightness = MonochromeProfile.Color.brightness
        result = controls.outputImage ?? result

        return result.applyingFilter("CISRGBToneCurveToLinear")
    }

    private func encode(_ image: CIImage, usedRAWPath: Bool) throws -> Output {
        guard let heic = context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: outputSpace,
            options: [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): LookProfile.Encode.quality
            ]
        ) else {
            throw CaptureError.renderFailed("HEIC encode failed")
        }

        return Output(heic: heic, usedRAWPath: usedRAWPath)
    }
}
