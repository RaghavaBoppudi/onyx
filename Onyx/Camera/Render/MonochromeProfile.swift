import CoreGraphics

enum MonochromeProfile {
    enum Color {
        static let contrast: Float = 1.05
        static let brightness: Float = 0.0
    }

    static let identityCurve: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1, y: 1)
    ]
}
