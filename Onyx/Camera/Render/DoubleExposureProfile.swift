import CoreGraphics

enum DoubleExposureProfile {
    static let exposureBias: Float = -1.0

    static let ghostOverlayOpacity: Double = 0.35

    static let previewMaxDimension: CGFloat = 640

    enum Curve {
        static let p0 = CGPoint(x: 0.00, y: 0.00)
        static let p1 = CGPoint(x: 0.25, y: 0.12)
        static let p2 = CGPoint(x: 0.50, y: 0.46)
        static let p3 = CGPoint(x: 0.80, y: 0.82)
        static let p4 = CGPoint(x: 1.00, y: 0.94)
    }

    enum Color {
        static let brightness: Float = -0.05
        static let blueFilterStrength: Float = 0.35
    }
}
