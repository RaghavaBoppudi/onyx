import CoreImage

struct OnyxFilterPipeline: Sendable {
    nonisolated(unsafe) private static let monoParams: [String: Any] = [
        "inputRVector": CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0),
        "inputGVector": CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0),
        "inputBVector": CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
    ]
    
    nonisolated(unsafe) private static let curveParams: [String: Any] = [
        "inputPoint0": CIVector(x: 0.0, y: 0.02),
        "inputPoint1": CIVector(x: 0.25, y: 0.14),
        "inputPoint2": CIVector(x: 0.50, y: 0.45),
        "inputPoint3": CIVector(x: 0.75, y: 0.65),
        "inputPoint4": CIVector(x: 1.0, y: 0.82)
    ]

    nonisolated static func apply(to image: CIImage) -> CIImage {
        let monoImage = image.applyingFilter("CIColorMatrix", parameters: monoParams)
        return monoImage.applyingFilter("CIToneCurve", parameters: curveParams)
    }
}
