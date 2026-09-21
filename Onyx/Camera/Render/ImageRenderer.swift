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
    private let doubleExposureChannelCurves: Data
    private let doubleExposureMonoLuminanceCurve: Data
    private let glassKernel: CIWarpKernel?
    private let glassShadingKernel: CIColorKernel?
    private let monoBlueFilterKernel: CIColorKernel?

    private var heldExposure: CIImage?

    init() {
        context = CIContext(options: [
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

        let doubleExposureCurvePoints = [
            DoubleExposureProfile.Curve.p0, DoubleExposureProfile.Curve.p1, DoubleExposureProfile.Curve.p2,
            DoubleExposureProfile.Curve.p3, DoubleExposureProfile.Curve.p4
        ]

        doubleExposureChannelCurves = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: doubleExposureCurvePoints,
            red: LookProfile.ChannelResponse.red,
            green: LookProfile.ChannelResponse.green,
            blue: LookProfile.ChannelResponse.blue,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )

        doubleExposureMonoLuminanceCurve = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: doubleExposureCurvePoints,
            red: MonochromeProfile.identityCurve,
            green: MonochromeProfile.identityCurve,
            blue: MonochromeProfile.identityCurve,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )

        glassKernel = CIWarpKernel(source: """
            kernel vec2 flutedGlassWarp(float sectionWidth, float maxDisplacement, vec2 axis) {
                float coord = dot(destCoord(), axis);
                float localCoord = (fract(coord / sectionWidth) - 0.5) * 2.0;
                float offset = (localCoord * localCoord * localCoord) * maxDisplacement;
                return destCoord() + (axis * offset);
            }
            """)
        if glassKernel == nil {
            Log.render.error("Glass warp kernel failed to compile")
        }

        glassShadingKernel = CIColorKernel(source: """
                    kernel vec4 flutedGlassShading(__sample image, float sectionWidth, float shadingStrength, float shadingSharpness, vec2 axis) {
                        float coord = dot(destCoord(), axis);
                        float localCoord = (fract(coord / sectionWidth) - 0.5) * 2.0;
                        float shade = sign(localCoord) * pow(abs(localCoord), shadingSharpness) * shadingStrength;
                        vec3 shaded = image.rgb * (1.0 + shade);
                        return vec4(clamp(shaded, 0.0, 1.0), image.a);
                    }
                    """)
        if glassShadingKernel == nil {
            Log.render.error("Glass shading kernel failed to compile")
        }

        monoBlueFilterKernel = CIColorKernel(source: """
                    kernel vec4 monoBlueFilter(__sample image, float strength) {
                        float baseLuma = dot(image.rgb, vec3(0.2126, 0.7152, 0.0722));
                        float blueBias = image.b - max(image.r, image.g);
                        float darken = clamp(blueBias, 0.0, 1.0) * strength;
                        float gray = clamp(baseLuma - darken, 0.0, 1.0);
                        return vec4(gray, gray, gray, image.a);
                    }
                    """)
        if monoBlueFilterKernel == nil {
            Log.render.error("Mono blue filter kernel failed to compile")
        }
    }

    func warmUp() {
        let synthetic = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = try? encode(applyLook(to: synthetic), usedRAWPath: false)
        _ = try? encode(applyMonochrome(to: synthetic), usedRAWPath: false)
        _ = try? encode(applyGlass(to: synthetic), usedRAWPath: false)
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
        let graded = grade(decoded, for: look)
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

        let graded = grade(source, for: look)
        return try encode(graded, usedRAWPath: false)
    }

    func beginDoubleExposure(_ shot: RawCapture, look: LookKind) throws -> Data {
        let decoded = try decodeRawExposure(shot)
        heldExposure = decoded
        let previewSource = look == .doubleExposureMono ? desaturated(decoded) : decoded
        return try downsizedPreview(previewSource)
    }

    func cancelDoubleExposure() {
        heldExposure = nil
    }

    func finishDoubleExposure(_ second: RawCapture, look: LookKind) throws -> Output {
        guard let first = heldExposure else {
            throw CaptureError.renderFailed("No held exposure for double exposure")
        }
        heldExposure = nil

        let secondDecoded = try decodeRawExposure(second)

        let blend = CIFilter.screenBlendMode()
        blend.inputImage = secondDecoded
        blend.backgroundImage = first
        let combined = (blend.outputImage ?? first).cropped(to: first.extent)

        let graded = grade(combined, for: look)
        return try encode(graded, usedRAWPath: second.isRAW)
    }

    private func desaturated(_ image: CIImage) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = 0
        return controls.outputImage ?? image
    }

    private func decodeRawExposure(_ shot: RawCapture) throws -> CIImage {
        if shot.isRAW {
            guard let filter = CIRAWFilter(imageData: shot.data, identifierHint: nil) else {
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
            filter.orientation = shot.orientation

            guard let decoded = filter.outputImage else {
                throw CaptureError.renderFailed("RAW decode produced no image")
            }
            return decoded
        } else {
            guard let source = CIImage(
                data: shot.data,
                options: [.applyOrientationProperty: true]
            ) else {
                throw CaptureError.renderFailed("Could not open processed image data")
            }
            return source
        }
    }

    private func downsizedPreview(_ image: CIImage, maxDimension: CGFloat = DoubleExposureProfile.previewMaxDimension) throws -> Data {
        let longestSide = max(image.extent.width, image.extent.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let jpeg = context.jpegRepresentation(
            of: scaled,
            colorSpace: outputSpace,
            options: [:]
        ) else {
            throw CaptureError.renderFailed("Ghost overlay preview encode failed")
        }
        return jpeg
    }

    private func grade(_ image: CIImage, for look: LookKind) -> CIImage {
        switch look {
        case .standard: applyLook(to: image)
        case .mono: applyMonochrome(to: image)
        case .glass: applyGlass(to: applyLook(to: image))
        case .doubleExposure: applyDoubleExposureLook(to: image)
        case .doubleExposureMono: applyDoubleExposureMonochrome(to: image)
        }
    }

    private func gradeTail(
        _ image: CIImage,
        curveData: Data,
        saturation: Float,
        contrast: Float,
        brightness: Float
    ) -> CIImage {
        let curves = CIFilter.colorCurves()
        curves.inputImage = image
        curves.curvesData = curveData
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.colorSpace = outputSpace
        let curved = curves.outputImage ?? image

        let controls = CIFilter.colorControls()
        controls.inputImage = curved
        controls.saturation = saturation
        controls.contrast = contrast
        controls.brightness = brightness
        let controlled = controls.outputImage ?? curved

        return controlled.applyingFilter("CISRGBToneCurveToLinear")
    }

    private func applyLook(to image: CIImage) -> CIImage {
        let linear = image.applyingFilter("CILinearToSRGBToneCurve")
        return gradeTail(
            linear,
            curveData: channelCurves,
            saturation: LookProfile.Color.saturation,
            contrast: LookProfile.Color.contrast,
            brightness: LookProfile.Color.brightness
        )
    }

    private func applyMonochrome(to image: CIImage) -> CIImage {
        let linear = image.applyingFilter("CILinearToSRGBToneCurve")

        let mono = CIFilter.colorMatrix()
        mono.inputImage = linear
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        mono.rVector = luma
        mono.gVector = luma
        mono.bVector = luma
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let desaturatedImage = mono.outputImage ?? linear

        return gradeTail(
            desaturatedImage,
            curveData: monoLuminanceCurve,
            saturation: 0,
            contrast: MonochromeProfile.Color.contrast,
            brightness: MonochromeProfile.Color.brightness
        )
    }

    private func applyDoubleExposureLook(to image: CIImage) -> CIImage {
        let linear = image.applyingFilter("CILinearToSRGBToneCurve")
        return gradeTail(
            linear,
            curveData: doubleExposureChannelCurves,
            saturation: LookProfile.Color.saturation,
            contrast: LookProfile.Color.contrast,
            brightness: DoubleExposureProfile.Color.brightness
        )
    }

    private func applyDoubleExposureMonochrome(to image: CIImage) -> CIImage {
        let linear = image.applyingFilter("CILinearToSRGBToneCurve")

        let filtered: CIImage
        if let monoBlueFilterKernel {
            filtered = monoBlueFilterKernel.apply(
                extent: linear.extent,
                arguments: [linear, DoubleExposureProfile.Color.blueFilterStrength]
            ) ?? linear
        } else {
            Log.render.error("Mono blue filter kernel unavailable, falling back to flat luma")
            let mono = CIFilter.colorMatrix()
            mono.inputImage = linear
            let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            mono.rVector = luma
            mono.gVector = luma
            mono.bVector = luma
            mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            filtered = mono.outputImage ?? linear
        }

        return gradeTail(
            filtered,
            curveData: doubleExposureMonoLuminanceCurve,
            saturation: 0,
            contrast: MonochromeProfile.Color.contrast,
            brightness: DoubleExposureProfile.Color.brightness
        )
    }

    private func applyGlass(to image: CIImage) -> CIImage {
        guard let glassKernel else {
            Log.render.error("Glass kernel unavailable, skipping warp")
            return image
        }

        let isPortrait = image.extent.height > image.extent.width
        let shortSide = isPortrait ? image.extent.width : image.extent.height
        let sectionWidth = Float(shortSide / CGFloat(GlassProfile.sectionCount))
        let displacement = Float(CGFloat(sectionWidth) * GlassProfile.maxDisplacementFactor)

        let axis = isPortrait ? CIVector(x: 1, y: 0) : CIVector(x: 0, y: 1)

        let dx = isPortrait ? CGFloat(-displacement) : 0
        let dy = isPortrait ? 0 : CGFloat(-displacement)

        let warped = glassKernel.apply(
                    extent: image.extent,
                    roiCallback: { _, rect in rect.insetBy(dx: dx, dy: dy) },
                    image: image.clampedToExtent(),
                    arguments: [sectionWidth, displacement, axis]
                )

        if warped == nil {
            Log.render.error("Glass warp apply() returned nil")
        }

        var result = warped ?? image

        if let glassShadingKernel {
                    let shaded = glassShadingKernel.apply(
                        extent: result.extent,
                        arguments: [
                            result,
                            sectionWidth,
                            Float(GlassProfile.shadingStrength),
                            Float(GlassProfile.shadingSharpness),
                            axis
                        ]
                    )
                    if shaded == nil {
                        Log.render.error("Glass shading apply() returned nil")
                    }
                    result = shaded ?? result
                }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = result
        blur.radius = Float(GlassProfile.frostBlurRadius)
        let frosted = blur.outputImage ?? result

        return frosted.cropped(to: image.extent)
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
