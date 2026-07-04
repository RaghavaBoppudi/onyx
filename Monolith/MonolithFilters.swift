import CoreImage
import CoreImage.CIFilterBuiltins

extension CIImage {
    func applyingMonolithMonochrome() -> CIImage? {
        let weights = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = self
        matrix.rVector = weights
        matrix.gVector = weights
        matrix.bVector = weights
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage
    }
    
    func applyingMonolithToneCurve() -> CIImage? {
        let curve = CIFilter.toneCurve()
        curve.inputImage = self
        curve.point0 = CGPoint(x: 0.0, y: 0.0)
        curve.point1 = CGPoint(x: 0.25, y: 0.15)
        curve.point2 = CGPoint(x: 0.50, y: 0.50)
        curve.point3 = CGPoint(x: 0.75, y: 0.75)
        curve.point4 = CGPoint(x: 1.0, y: 1.0)
        return curve.outputImage
    }
}
