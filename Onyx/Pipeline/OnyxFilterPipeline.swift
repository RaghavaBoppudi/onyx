import CoreImage
import CoreImage.CIFilterBuiltins

struct OnyxFilterPipeline: Sendable {
    nonisolated static func apply(to image: CIImage) -> CIImage {
        let monoFilter = CIFilter.colorMatrix()
        monoFilter.inputImage = image
        monoFilter.rVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monoFilter.gVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monoFilter.bVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monoFilter.aVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
        
        guard let monoImage = monoFilter.outputImage else { return image }
        
        let curveFilter = CIFilter.toneCurve()
        curveFilter.inputImage = monoImage
        curveFilter.point0 = CGPoint(x: 0.0, y: 0.02)
        curveFilter.point1 = CGPoint(x: 0.25, y: 0.14)
        curveFilter.point2 = CGPoint(x: 0.50, y: 0.45)
        curveFilter.point3 = CGPoint(x: 0.75, y: 0.65)
        curveFilter.point4 = CGPoint(x: 1.0, y: 0.82)
        
        return curveFilter.outputImage ?? monoImage
    }
}
