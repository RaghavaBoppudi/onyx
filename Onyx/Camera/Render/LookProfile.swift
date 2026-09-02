import CoreGraphics

enum LookProfile {

    enum Decode {
        static let boostAmount: Float = 0
        static let boostShadowAmount: Float = 0
        static let localToneMapAmount: Float = 0
        static let extendedDynamicRangeAmount: Float = 0
        static let baselineExposure: Float = 0
        static let luminanceNoiseReduction: Float = 0
        static let colorNoiseReduction: Float = 0
        static let sharpness: Float = 0
        static let detail: Float = 0
        static let contrast: Float = 0
    }

    enum Curve {
        static let p0 = CGPoint(x: 0.00, y: 0.00)
        static let p1 = CGPoint(x: 0.22, y: 0.250)
        static let p2 = CGPoint(x: 0.50, y: 0.500)
        static let p3 = CGPoint(x: 0.80, y: 0.925)
        static let p4 = CGPoint(x: 1.00, y: 1.000)
    }

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

        static let sampleCount = 64
    }

    enum Color {
        static let saturation: Float = 1.02
        static let contrast: Float = 1.0
        static let brightness: Float = 0.0
    }

    enum Encode {
        static let quality: Double = 0.92
    }
}
