//  ImageRenderer.swift
//  RAW mosaic in, finished HEIC out. Nothing else in the app produces image bytes.
//
//  The DNG never reaches disk. It exists for exactly as long as it takes to decode
//  with Apple's tone curve switched off, which is the only way to make our curve the
//  first and only curve applied.
//
//  Colour space: Core Image works in extended linear sRGB, but LookProfile's curves
//  are drawn in perceptual terms — "0.5 is a midtone" is a statement about gamma
//  space. The look is bracketed by an explicit gamma round-trip: linear → sRGB,
//  shape, sRGB → linear. Core Image then encodes gamma exactly once.
//
//  RENDERING IS CPU-ONLY. `.useSoftwareRenderer: true` below.
//
//  An earlier build ran this context on Metal and crashed on the 11 Pro with
//  'AGXA13FamilyFunctionHandle resourceIndex' — a driver-level trap, not a Swift
//  error, uncatchable by any `catch` block. The first fix assumed the crash came
//  from fusing CIRAWFilter's lazy demosaic graph with the look filters chained on
//  top of it, and materialized the decode into a real CGImage before applying the
//  look to break that fusion apart. It crashed again, at the same signature. That
//  result is actually informative: materializing forces the demosaic to execute
//  at that point rather than later, and the trap still fired there — which means
//  the fault is inside CIRAWFilter's own compiled kernel on this A13 / iOS 27
//  pairing, not in anything downstream that our filter graph controls. No
//  restructuring on our side reaches code we don't own.
//
//  The only lever left is not running it on the GPU. Every render in this app
//  — RAW decode, the look filters, HEIC encode — now goes through Core
//  Image's software rasterizer. This is categorically slower: full CPU RAW
//  demosaic plus a multi-pass filter chain on a 12 MP image, on an A13, is a real
//  multi-second cost per shot. It is happening in `CameraModel.develop(_:)`,
//  which already runs after the shutter has returned control to the user — so
//  the capture itself stays instant and the cost lands entirely in the wait
//  before the thumbnail appears, not before the next shot can be taken.
//
//  This is very plausibly an iOS 27 beta regression in Core Image's Metal RAW
//  path on A13-class GPUs rather than anything reachable from application code —
//  worth a Feedback report to Apple — but the app needs to not crash regardless
//  of whose bug it is, so software rendering stays until there's a signal the
//  underlying driver issue is fixed.

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

    init() {
        context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false
        ])

        channelCurves = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: [
                LookProfile.Curve.p0, LookProfile.Curve.p1, LookProfile.Curve.p2,
                LookProfile.Curve.p3, LookProfile.Curve.p4
            ],
            red: LookProfile.ChannelResponse.red,
            green: LookProfile.ChannelResponse.green,
            blue: LookProfile.ChannelResponse.blue,
            sampleCount: LookProfile.ChannelResponse.sampleCount
        )
    }

    /// Forces the look/encode filter chain to JIT-compile once, off the capture
    /// path — Core Image compiles kernels lazily on first use per process, and
    /// without this the cost lands on whichever shot happens to be first.
    ///
    /// This does NOT warm `CIRAWFilter`'s own demosaic kernel — that only compiles
    /// against real RAW image data, and nothing exists at launch to warm it with.
    /// The first real shot will likely still be slower than the rest; this removes
    /// the look-and-encode portion of that cost, not all of it.
    func warmUp() {
        let synthetic = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = try? encode(applyLook(to: synthetic), usedRAWPath: false)
    }

    // MARK: - RAW path

    func renderRAW(
        dngData: Data,
        orientation: CGImagePropertyOrientation
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

        // A DNG carries no orientation of its own — AVFoundation never applies
        // sensor orientation compensation to RAW — so the decoder is told which way
        // is up and reads the mosaic accordingly.
        filter.orientation = orientation

        guard let decoded = filter.outputImage else {
            throw CaptureError.renderFailed("RAW decode produced no image")
        }

        Log.render.debug("RAW path, orientation \(orientation.rawValue)")
        return try encode(applyLook(to: decoded), usedRAWPath: true)
    }

    // MARK: - Fallback path

    /// For optics that expose no Bayer format.
    ///
    /// Orientation here is the opposite problem to the RAW path, and getting the two
    /// confused is what rotated the ultra-wide captures. A processed photo from
    /// AVCapturePhotoOutput has **already** been oriented — sensor compensation is
    /// applied to HEIC and JPEG, and the EXIF tag is set from the connection's
    /// rotation angle. Applying our own orientation on top of that rotates it a
    /// second time. So we let Core Image honour the tag that is already in the file
    /// and add nothing.
    func renderProcessed(
        imageData: Data,
        orientation: CGImagePropertyOrientation
    ) throws -> Output {
        guard let source = CIImage(
            data: imageData,
            options: [.applyOrientationProperty: true]
        ) else {
            throw CaptureError.renderFailed("Could not open processed image data")
        }

        let embedded = (source.properties[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
        Log.render.debug(
            "ISP fallback path, embedded orientation \(embedded), capture angle implied \(orientation.rawValue)"
        )

        return try encode(applyLook(to: source), usedRAWPath: false)
    }

    // MARK: - The look
    //
    // Four passes now, not five: the luminance tone curve used to be its own
    // CIFilter.toneCurve() call before the channel curves ran. It's composed into
    // `channelCurves` instead (see ToneCurveSampler), so a single CIColorCurves
    // call now does the work of both — same output, one less full-image pass.

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

    // MARK: - Encode

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
