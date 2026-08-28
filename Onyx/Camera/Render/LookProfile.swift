//  LookProfile.swift
//  THE aesthetic file. Onyx's entire visual identity is these numbers.
//
//  Three stages, in order:
//
//  1. NEUTRALISE. `boostAmount = 0` switches off Apple's default tone curve and
//     returns a near-linear render of the mosaic. Every other decode knob is zeroed
//     for the same reason. This is not a look — it is the removal of someone else's
//     look, so that ours is the only one applied.
//
//  2. TONE. One S-curve shaping luminance. Stands in for what a small CCD did
//     mechanically: shadows fall away early, midtones carry the contrast, and
//     highlights hit the ceiling and stop rather than rolling off.
//
//  3. COLOUR. Three independent channel curves. This is where the warmth lives.
//
//  Why channel curves instead of a temperature shift: a global warm shift warms
//  everything, shadows included, and muddy warm shadows are the fastest way to make
//  an image read as filtered rather than photographed. Separate R, G and B responses
//  let shadows stay neutral while midtones and highlights warm — which is what a
//  Canon compact actually did, because the warmth came from the colour matrix and
//  the highlight response, not from the white balance.

import CoreGraphics

enum LookProfile {

    // MARK: - Stage 1 — neutralise the RAW decode

    enum Decode {
        /// 0 disables Apple's tone curve. This single line is why the app captures
        /// RAW internally at all.
        static let boostAmount: Float = 0
        static let boostShadowAmount: Float = 0
        /// Local tone mapping is the per-region exposure lift that makes modern
        /// phone photos read as "HDR". Off.
        static let localToneMapAmount: Float = 0
        static let extendedDynamicRangeAmount: Float = 0
        static let baselineExposure: Float = 0

        // Everything below is zero on purpose, and every one of these has a
        // non-zero Apple default — leaving them unset would silently reintroduce
        // exactly the processing this app exists to avoid.
        //
        // Consequence, stated plainly: chroma noise is now untouched. In shadows on
        // a 2019 sensor that shows as coloured speckle, which is a digital artefact
        // rather than film-like grain — no CCD ever produced it, because their
        // noise characteristics were different. If it reads as dirt rather than as
        // texture, `colorNoiseReduction` around 0.3 kills the speckle while leaving
        // luminance grain intact. That is the only one of these four I would
        // reconsider.
        static let luminanceNoiseReduction: Float = 0
        static let colorNoiseReduction: Float = 0
        static let sharpness: Float = 0
        static let detail: Float = 0
        static let contrast: Float = 0
    }

    // MARK: - Stage 2 — luminance

    /// Five control points, normalised 0...1, applied in gamma space.
    /// p0 anchors black, p1 is the toe, p2 the midtone pivot, p3 the shoulder,
    /// p4 anchors white.
    ///
    /// p3 is the CCD signature: the top 20% of input compresses into the last 7.5%
    /// of output, so bright areas flatten with an edge instead of a gradient. A
    /// modern phone pipeline spends its entire budget preventing exactly this.
    enum Curve {
        // Very slight lift off true black — the request was "shadows stay intact,
        // maybe a very slight bump," not a real change here.
        static let p0 = CGPoint(x: 0.00, y: 0.00)
        // The actual fix. Was (0.22, 0.210) — a softened crush, still below the
        // diagonal. Now above it: a real lift at the shadow/midtone boundary, not
        // a smaller version of the old crush. This is the point doing the work.
        static let p1 = CGPoint(x: 0.22, y: 0.250)
        // Back to pure identity. The lift at p1 is meant to ease back to the
        // diagonal by the time you reach actual midtones, not carry through them.
        static let p2 = CGPoint(x: 0.50, y: 0.500)
        // UNCHANGED, pending confirmation — see the note above Curve. This is the
        // CCD shoulder from early in the look's design: highlights clip with a
        // firm edge rather than a soft rolloff. "No adjustment to the rest" could
        // mean keep this as-is, or could mean flatten it to identity too — I kept
        // it rather than silently discard a previously deliberate design choice.
        static let p3 = CGPoint(x: 0.80, y: 0.925)   // firm shoulder
        static let p4 = CGPoint(x: 1.00, y: 1.000)
    }

    // MARK: - Stage 3 — colour

    /// Read these vertically. At 0.20 the channels are within 0.004 — shadows
    /// neutral. At 0.50 red leads blue by ~3% — the warmth. At 1.00 blue caps at
    /// 0.976, so clipped highlights go cream rather than white, which is the most
    /// recognisable single trait of that generation of Canon compact.
    ///
    /// Keep the spread small. Past roughly 6% at the midpoint this stops looking
    /// like a camera and starts looking like a filter.
    enum ChannelResponse {
        static let red: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.000),
            CGPoint(x: 0.20, y: 0.204),
            CGPoint(x: 0.50, y: 0.518),
            CGPoint(x: 0.80, y: 0.812),
            CGPoint(x: 1.00, y: 1.000)
        ]

        static let green: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.000),
            CGPoint(x: 0.20, y: 0.201),
            CGPoint(x: 0.50, y: 0.503),
            CGPoint(x: 0.80, y: 0.798),
            CGPoint(x: 1.00, y: 0.994)
        ]

        static let blue: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.000),
            CGPoint(x: 0.20, y: 0.200),
            CGPoint(x: 0.50, y: 0.489),
            CGPoint(x: 0.80, y: 0.776),
            CGPoint(x: 1.00, y: 0.976)
        ]

        /// Raise to 128 if gradients band.
        static let sampleCount = 64
    }

    enum Color {
        /// Barely above neutral. Canon compacts read as punchy because of contrast
        /// and the channel response, not saturation.
        static let saturation: Float = 1.02
        /// The tone curve owns contrast.
        static let contrast: Float = 1.0
        static let brightness: Float = 0.0
    }

    enum Encode {
        static let quality: Double = 0.92
    }
}
