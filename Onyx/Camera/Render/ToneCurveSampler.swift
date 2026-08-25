//  ToneCurveSampler.swift
//  Turns LookProfile's control points into the flat sample buffer CIColorCurves
//  wants.
//
//  Monotone cubic Hermite (Fritsch–Carlson), not linear and not Catmull-Rom.
//  Linear interpolation between five points leaves visible kinks in skies and skin.
//  Catmull-Rom is smooth but can overshoot, which on a colour curve means a channel
//  briefly rising above its neighbours and putting a coloured fringe in a gradient.
//  Fritsch–Carlson is smooth and provably never overshoots, which is exactly the
//  guarantee a tone curve needs.

import CoreGraphics
import Foundation

enum ToneCurveSampler {

    /// Interleaved RGB float samples across the 0...1 domain, ready for
    /// `CIColorCurves.curvesData`.
    static func interleavedRGBData(
        red: [CGPoint],
        green: [CGPoint],
        blue: [CGPoint],
        sampleCount: Int
    ) -> Data {
        let r = sample(red, count: sampleCount)
        let g = sample(green, count: sampleCount)
        let b = sample(blue, count: sampleCount)

        var values: [Float] = []
        values.reserveCapacity(sampleCount * 3)
        for i in 0..<sampleCount {
            values.append(r[i])
            values.append(g[i])
            values.append(b[i])
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func sample(_ points: [CGPoint], count: Int) -> [Float] {
        guard points.count >= 2, count >= 2 else {
            return Array(repeating: 0, count: max(count, 0))
        }

        let sorted = points.sorted { $0.x < $1.x }
        let xs = sorted.map { Double($0.x) }
        let ys = sorted.map { Double($0.y) }
        let tangents = monotoneTangents(xs: xs, ys: ys)

        return (0..<count).map { index in
            let x = Double(index) / Double(count - 1)
            let y = evaluate(x: x, xs: xs, ys: ys, tangents: tangents)
            return Float(min(max(y, 0), 1))
        }
    }

    // MARK: - Fritsch–Carlson

    private static func monotoneTangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        guard n > 1 else { return [0] }

        // Secant slopes between consecutive points.
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

    private static func evaluate(
        x: Double, xs: [Double], ys: [Double], tangents: [Double]
    ) -> Double {
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
}
