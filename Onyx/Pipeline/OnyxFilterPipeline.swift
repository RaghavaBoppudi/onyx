import CoreImage
import CoreImage.CIFilterBuiltins

struct OnyxFilterPipeline: Sendable {
    nonisolated static func apply(to image: CIImage) -> CIImage {
        let monochrome = CIFilter.colorMatrix()
        monochrome.rVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.gVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.bVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        monochrome.inputImage = image
        
        guard let monoImage = monochrome.outputImage else { return image }
        
        let curve = CIFilter.toneCurve()
        curve.point0 = CGPoint(x: 0.0, y: 0.02)
        curve.point1 = CGPoint(x: 0.25, y: 0.14)
        curve.point2 = CGPoint(x: 0.50, y: 0.45)
        curve.point3 = CGPoint(x: 0.75, y: 0.65)
        curve.point4 = CGPoint(x: 1.0, y: 0.82)
        curve.inputImage = monoImage
        
        return curve.outputImage ?? monoImage
    }
}
