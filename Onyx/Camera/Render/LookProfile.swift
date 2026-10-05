import CoreGraphics

enum LookProfile {
    static let toneCurve: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.00),
        CGPoint(x: 0.22, y: 0.250),
        CGPoint(x: 0.50, y: 0.500),
        CGPoint(x: 0.80, y: 0.925),
        CGPoint(x: 1.00, y: 1.000)
    ]

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

    static let saturation: Float = 1.02
    static let encodeQuality: Double = 0.92
}

enum MonochromeProfile {
    static let contrast: Float = 1.05
    static let identityCurve: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1, y: 1)
    ]
}

enum DoubleExposureProfile {
    static let exposureBias: Float = -1.0
    static let ghostOverlayOpacity: Double = 0.35
    static let previewMaxDimension: CGFloat = 640
    static let brightness: Float = -0.05
    static let blueFilterStrength: Float = 0.35

    static let toneCurve: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.00),
        CGPoint(x: 0.25, y: 0.12),
        CGPoint(x: 0.50, y: 0.46),
        CGPoint(x: 0.80, y: 0.82),
        CGPoint(x: 1.00, y: 0.94)
    ]
}

enum GlassProfile {
    static let sectionCount: Float = 25
    static let maxDisplacementFactor: Float = 6.0
    static let frostBlurRadius: Float = 0.5
    static let shadingStrength: Float = 0.4
    static let shadingSharpness: Float = 6.0
}
