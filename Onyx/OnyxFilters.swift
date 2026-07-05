import CoreImage
import CoreImage.CIFilterBuiltins

extension CIImage {
    func applyingOnyxMonochrome() -> CIImage? {
        let weights = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = self
        matrix.rVector = weights
        matrix.gVector = weights
        matrix.bVector = weights
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage
    }
    
    func applyingOnyxToneCurve() -> CIImage? {
        let curve = CIFilter.toneCurve()
        curve.inputImage = self
        
        // Point 0: Film base + fog. Barely lifted above pure digital black (0.0).
        curve.point0 = CGPoint(x: 0.0, y: 0.0)
        
        // Point 1: Deep shadows for density and structural punch.
        curve.point1 = CGPoint(x: 0.25, y: 0.15)
        
        // Point 2: Midtone anchor.
        curve.point2 = CGPoint(x: 0.50, y: 0.50)
        
        // Point 3: Flattened shoulder. Protects highlights from blowing out.
        curve.point3 = CGPoint(x: 0.75, y: 0.75)
        
        // Point 4: Compressed white point. Creates the creamy, optical print roll-off.
        curve.point4 = CGPoint(x: 1.0, y: 1.0)
        
        return curve.outputImage
    }
}
