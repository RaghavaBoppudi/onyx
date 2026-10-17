import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import os

nonisolated extension CIImage {
    func horizontallyMirrored() -> CIImage {
        let flipped = transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        return flipped.transformed(
            by: CGAffineTransform(translationX: -flipped.extent.minX, y: -flipped.extent.minY)
        )
    }
}

actor ImageRenderer {

    nonisolated struct Output: Sendable {
        let heic: Data
        let usedRAWPath: Bool
        let isDegraded: Bool
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let standardCurves: Data
    private let monoCurves: Data
    private let doubleExposureCurves: Data
    private let doubleExposureMonoCurves: Data
    private let monoBlueFilterKernel: CIColorKernel?

    private var heldExposure: CIImage?

    init() {
        standardCurves = Self.curves(tone: LookProfile.toneCurve, mono: false)
        monoCurves = Self.curves(tone: LookProfile.toneCurve, mono: true)
        doubleExposureCurves = Self.curves(tone: DoubleExposureProfile.toneCurve, mono: false)
        doubleExposureMonoCurves = Self.curves(tone: DoubleExposureProfile.toneCurve, mono: true)

        let library = Self.metalLibraryData()
        monoBlueFilterKernel = Self.colorKernel("monoBlueFilter", in: library)

        Log.render.info("Kernels loaded: monoBlue=\(self.monoBlueFilterKernel != nil)")
    }

    private static func colorKernel(_ name: String, in library: Data?) -> CIColorKernel? {
        guard let library else { return nil }
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: library)
        } catch {
            Log.render.error("Kernel \(name, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isDegraded(_ mode: CaptureMode) -> Bool {
        mode == .doubleExposureMono && monoBlueFilterKernel == nil
    }

    private static func metalLibraryData() -> Data? {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else {
            Log.render.error("Core Image Metal library not found; the Mono blue filter is disabled")
            return nil
        }
        return data
    }

    func warmUp() {
        let synthetic = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        for mode in CaptureMode.allCases {
            _ = try? encode(grade(synthetic, for: mode), usedRAWPath: false)
        }
    }

    func render(_ shot: RawCapture, request: CaptureRequest) throws -> Output {
        let decoded = try decode(shot, request: request)
        let graded = request.position == .front && !shot.isRAW
            ? gradeProcessed(decoded, for: request.mode)
            : grade(decoded, for: request.mode)
        return try encode(graded, usedRAWPath: shot.isRAW, isDegraded: isDegraded(request.mode))
    }

    func renderDual(
        _ frames: DualFrames,
        rearOrientation: CGImagePropertyOrientation,
        frontOrientation: CGImagePropertyOrientation,
        style: DualLayoutStyle
    ) throws -> Output {
        let composite = DualCompositor.compose(
            frames: frames,
            rearOrientation: rearOrientation,
            frontOrientation: frontOrientation,
            mirrorsFront: FrontCameraPipeline.mirrorsSavedImage,
            style: style
        )
        return try encode(composite, usedRAWPath: false)
    }

    func beginDoubleExposure(_ shot: RawCapture, request: CaptureRequest) throws -> Data {
        let decoded = try decode(shot, request: request)
        heldExposure = decoded
        return try previewJPEG(request.mode.isMono ? desaturated(decoded) : decoded)
    }

    func cancelDoubleExposure() {
        heldExposure = nil
    }

    func finishDoubleExposure(
        _ second: RawCapture,
        request: CaptureRequest
    ) throws -> Output {
        guard let first = heldExposure else {
            throw CaptureError.renderFailed("No held exposure for double exposure")
        }
        heldExposure = nil

        let blend = CIFilter.screenBlendMode()
        blend.inputImage = try decode(second, request: request)
        blend.backgroundImage = first
        let combined = (blend.outputImage ?? first).cropped(to: first.extent)

        return try encode(
            grade(combined, for: request.mode),
            usedRAWPath: second.isRAW,
            isDegraded: isDegraded(request.mode)
        )
    }

    private static func curves(tone: [CGPoint], mono: Bool) -> Data {
        ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: tone,
            red: mono ? MonochromeProfile.identityCurve : LookProfile.ChannelResponse.red,
            green: mono ? MonochromeProfile.identityCurve : LookProfile.ChannelResponse.green,
            blue: mono ? MonochromeProfile.identityCurve : LookProfile.ChannelResponse.blue,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )
    }

    private func decode(_ shot: RawCapture, request: CaptureRequest) throws -> CIImage {
        guard shot.isRAW else {
            guard let source = CIImage(data: shot.data, options: [.applyOrientationProperty: true]) else {
                throw CaptureError.renderFailed("Could not open processed image data")
            }
            guard request.position == .front else { return source }

            let framed = cropped(source, toAspect: request.isPortrait ? 3.0 / 4.0 : 4.0 / 3.0)
            return FrontCameraPipeline.mirrorsSavedImage ? framed.horizontallyMirrored() : framed
        }

        guard let filter = CIRAWFilter(imageData: shot.data, identifierHint: nil) else {
            throw CaptureError.renderFailed("Could not open RAW data")
        }
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        filter.extendedDynamicRangeAmount = 0
        filter.baselineExposure = 0
        filter.luminanceNoiseReductionAmount = 0
        filter.colorNoiseReductionAmount = 0
        filter.sharpnessAmount = 0
        filter.detailAmount = 0
        filter.contrastAmount = 0
        filter.orientation = shot.orientation

        guard let decoded = filter.outputImage else {
            throw CaptureError.renderFailed("RAW decode produced no image")
        }
        return decoded
    }

    private func cropped(_ image: CIImage, toAspect target: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let current = extent.width / extent.height
        guard abs(current - target) > 0.005 else { return image }

        var size = extent.size
        if current > target {
            size.width = extent.height * target
        } else {
            size.height = extent.width / target
        }

        let rect = CGRect(
            x: extent.midX - size.width / 2,
            y: extent.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral

        return image.cropped(to: rect)
    }

    private func gradeProcessed(_ image: CIImage, for mode: CaptureMode) -> CIImage {
        switch mode {
        case .standard:
            return image
        case .mono:
            return luma(image.applyingFilter("CILinearToSRGBToneCurve"))
                .applyingFilter("CISRGBToneCurveToLinear")
        case .doubleExposure, .doubleExposureMono:
            return grade(image, for: mode)
        }
    }

    private func grade(_ image: CIImage, for mode: CaptureMode) -> CIImage {
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")

        switch mode {
        case .standard:
            return applyCurves(encoded, curves: standardCurves, saturation: LookProfile.saturation)
        case .mono:
            return applyCurves(
                luma(encoded),
                curves: monoCurves,
                saturation: 0,
                contrast: MonochromeProfile.contrast
            )
        case .doubleExposure:
            return applyCurves(
                encoded,
                curves: doubleExposureCurves,
                saturation: LookProfile.saturation,
                brightness: DoubleExposureProfile.brightness
            )
        case .doubleExposureMono:
            return applyCurves(
                blueFilteredMono(encoded),
                curves: doubleExposureMonoCurves,
                saturation: 0,
                contrast: MonochromeProfile.contrast,
                brightness: DoubleExposureProfile.brightness
            )
        }
    }

    private func applyCurves(
        _ image: CIImage,
        curves: Data,
        saturation: Float,
        contrast: Float = 1,
        brightness: Float = 0
    ) -> CIImage {
        let curveFilter = CIFilter.colorCurves()
        curveFilter.inputImage = image
        curveFilter.curvesData = curves
        curveFilter.curvesDomain = CIVector(x: 0, y: 1)
        curveFilter.colorSpace = outputSpace
        let curved = curveFilter.outputImage ?? image

        let controls = CIFilter.colorControls()
        controls.inputImage = curved
        controls.saturation = saturation
        controls.contrast = contrast
        controls.brightness = brightness

        return (controls.outputImage ?? curved).applyingFilter("CISRGBToneCurveToLinear")
    }

    private func luma(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        filter.rVector = weights
        filter.gVector = weights
        filter.bVector = weights
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    private func blueFilteredMono(_ image: CIImage) -> CIImage {
        guard let kernel = monoBlueFilterKernel,
              let filtered = kernel.apply(
                extent: image.extent,
                arguments: [image, DoubleExposureProfile.blueFilterStrength]
              )
        else {
            Log.render.error("Mono blue filter unavailable, falling back to flat luma")
            return luma(image)
        }
        return filtered
    }

    private func desaturated(_ image: CIImage) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = 0
        return controls.outputImage ?? image
    }

    private func previewJPEG(_ image: CIImage) throws -> Data {
        let maxDimension = DoubleExposureProfile.previewMaxDimension
        let longestSide = max(image.extent.width, image.extent.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let jpeg = self.context.jpegRepresentation(of: scaled, colorSpace: outputSpace, options: [:]) else {
            throw CaptureError.renderFailed("Ghost overlay preview encode failed")
        }
        return jpeg
    }

    private func encode(_ image: CIImage, usedRAWPath: Bool, isDegraded: Bool = false) throws -> Output {
        guard let heic = self.context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: outputSpace,
            options: [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): LookProfile.encodeQuality
            ]
        ) else {
            throw CaptureError.renderFailed("HEIC encode failed")
        }

        return Output(heic: heic, usedRAWPath: usedRAWPath, isDegraded: isDegraded)
    }
}
