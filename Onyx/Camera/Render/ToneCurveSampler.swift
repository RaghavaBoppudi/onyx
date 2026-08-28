//  ToneCurveSampler.swift
//  Samples LookProfile's curves into the flat LUT buffer CIColorCurves wants — and
//  composes the luminance tone curve into that same LUT ahead of time, so Core
//  Image only has to walk the image once for both effects combined.
//
//  Composing rather than chaining two CIFilter passes (CIToneCurve, then
//  CIColorCurves) produces the identical final image: both are simple per-channel
//  monotone remaps, and applying f then g to a value is the same result whether
//  Core Image does it in two image-wide passes or Swift precomputes g(f(x)) once
//  per LUT entry and Core Image applies the combined result in one. On a 12 MP
//  image that's one fewer full-image filter pass, for every device, with zero
//  change to what the photo looks like.
//
//  Monotone cubic Hermite (Fritsch–Carlson), not linear and not Catmull-Rom. Linear
//  interpolation between five points leaves visible kinks in skies and skin.
//  Catmull-Rom is smooth but can overshoot, which on a colour curve means a channel
//  briefly rising above its neighbours — a coloured fringe in a gradient.
//  Fritsch–Carlson is smooth and provably never overshoots.

import CoreGraphics
import Foundation

enum ToneCurveSampler {

    /// Builds the interleaved RGB LUT for `CIColorCurves`, with `toneCurve`
    /// pre-composed into each channel.
    static func composedInterleavedRGBData(
        toneCurve: [CGPoint],
        red: [CGPoint],
        green: [CGPoint],
        blue: [CGPoint],
        sampleCount: Int
    ) -> Data {
        let tone = CurveEvaluator(points: toneCurve)
        let r = CurveEvaluator(points: red)
        let g = CurveEvaluator(points: green)
        let b = CurveEvaluator(points: blue)

        let count = max(sampleCount, 2)
        var values: [Float] = []
        values.reserveCapacity(count * 3)

        for i in 0..<count {
            let x = Double(i) / Double(count - 1)
            let toned = tone.evaluate(x)
            values.append(clamped(r.evaluate(toned)))
            values.append(clamped(g.evaluate(toned)))
            values.append(clamped(b.evaluate(toned)))
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func clamped(_ value: Double) -> Float {
        Float(min(max(value, 0), 1))
    }
}

/// A single monotone curve, evaluable at any point in its domain — not just at
/// fixed grid positions. Composition (feeding one curve's output into another as
/// input) needs that; sampling onto a fixed grid alone doesn't allow it.
struct CurveEvaluator {
    private let xs: [Double]
    private let ys: [Double]
    private let tangents: [Double]

    init(points: [CGPoint]) {
        let sorted = points.sorted { $0.x < $1.x }
        xs = sorted.map { Double($0.x) }
        ys = sorted.map { Double($0.y) }
        tangents = Self.monotoneTangents(xs: xs, ys: ys)
    }

    func evaluate(_ x: Double) -> Double {
        guard xs.count >= 2 else { return ys.first ?? x }
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }

        var segment = 0
        for i in 0..<(xs.count - 1) where x >= xs[i] && x <= xs[i + 1] {
            segment = i
            break
        }

        let h = xs[segment + 1] - xs[segment]
        guard h > 0 else { return ys[segment] }
        let t = (x - xs[segment]) / h
        let t2 = t * t
        let t3 = t2 * t

        // Hermite basis.
        let h00 =  2 * t3 - 3 * t2 + 1
        let h10 =      t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 =      t3 -     t2

        return h00 * ys[segment]
             + h10 * h * tangents[segment]
             + h01 * ys[segment + 1]
             + h11 * h * tangents[segment + 1]
    }

    // MARK: - Fritsch–Carlson

    private static func monotoneTangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        guard n > 1 else { return [0] }

        var slopes = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = xs[i + 1] - xs[i]
            slopes[i] = dx == 0 ? 0 : (ys[i + 1] - ys[i]) / dx
        }

        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = (slopes[i - 1] + slopes[i]) / 2
        }

        // Clamp so the curve can never reverse direction between control points.
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let a = tangents[i] / slopes[i]
            let b = tangents[i + 1] / slopes[i]
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let scale = 3 / magnitude.squareRoot()
                tangents[i] = scale * a * slopes[i]
                tangents[i + 1] = scale * b * slopes[i]
            }
        }
        return tangents
    }
}
