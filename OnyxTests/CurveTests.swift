import CoreGraphics
import Foundation
import Testing
@testable import Onyx

struct CurveTests {

    @Test func evaluatorPassesThroughItsControlPoints() {
        let curve = CurveEvaluator(points: LookProfile.toneCurve)
        for point in LookProfile.toneCurve {
            #expect(abs(curve.evaluate(Double(point.x)) - Double(point.y)) < 1e-9)
        }
    }

    @Test func evaluatorNeverReversesDirection() {
        let curve = CurveEvaluator(points: LookProfile.toneCurve)
        var previous = -Double.infinity
        for step in 0...400 {
            let value = curve.evaluate(Double(step) / 400)
            #expect(value >= previous - 1e-9)
            previous = value
        }
    }

    @Test func evaluatorClampsOutsideItsDomain() {
        let curve = CurveEvaluator(points: LookProfile.toneCurve)
        #expect(curve.evaluate(-1) == 0)
        #expect(curve.evaluate(2) == 1)
    }

    @Test func samplerProducesInterleavedFloatsInRange() {
        let data = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: LookProfile.toneCurve,
            red: LookProfile.ChannelResponse.red,
            green: LookProfile.ChannelResponse.green,
            blue: LookProfile.ChannelResponse.blue,
            sampleCount: 64
        )
        #expect(data.count == 64 * 3 * MemoryLayout<Float>.size)

        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(values.allSatisfy { (0...1).contains($0) })
        #expect(values.first == 0)
    }

    @Test func identityCurvesSampleToAStraightRamp() {
        let identity = MonochromeProfile.identityCurve
        let data = ToneCurveSampler.composedInterleavedRGBData(
            toneCurve: identity, red: identity, green: identity, blue: identity, sampleCount: 11
        )
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        for index in 0..<11 {
            let expected = Float(index) / 10
            #expect(abs(values[index * 3] - expected) < 1e-4)
        }
    }
}
