import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

struct PhotoProcessor {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    private func decodeRAW(data: Data) -> CIImage? {
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        rawFilter.luminanceNoiseReductionAmount = 0.0
        rawFilter.colorNoiseReductionAmount = 0.0
        rawFilter.sharpnessAmount = 0.0
        rawFilter.extendedDynamicRangeAmount = 0.0
        rawFilter.localToneMapAmount = 0.0
        rawFilter.boostAmount = 0.0
        return rawFilter.outputImage
    }
    
    func processAndSave(photoData: Data, secondaryData: Data?, location: CLLocation?) {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let baseRaw = self.decodeRAW(data: photoData) else { return }
                
                // 1. Base Monochrome Conversion
                let weights = CIVector(x: 0.90, y: 0.10, z: 0.00, w: 0.0)
                let ccd1 = CIFilter.colorMatrix()
                ccd1.inputImage = baseRaw
                ccd1.rVector = weights; ccd1.gVector = weights; ccd1.bVector = weights
                ccd1.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
                
                guard let baseMono = ccd1.outputImage else { return }
                var finalImage: CIImage
                
                let toneCurve = CIFilter.toneCurve()
                toneCurve.point0 = CGPoint(x: 0.0, y: 0.0)
                toneCurve.point1 = CGPoint(x: 0.25, y: 0.15)
                toneCurve.point2 = CGPoint(x: 0.50, y: 0.50)
                toneCurve.point3 = CGPoint(x: 0.75, y: 0.75)
                toneCurve.point4 = CGPoint(x: 1.0, y: 1.0)
                
                if let secondaryData = secondaryData, let secondRaw = self.decodeRAW(data: secondaryData) {
                    // DOUBLE EXPOSURE: Decode -> Blend -> Expose -> Curve
                    let ccd2 = CIFilter.colorMatrix()
                    ccd2.inputImage = secondRaw
                    ccd2.rVector = weights; ccd2.gVector = weights; ccd2.bVector = weights
                    ccd2.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
                    
                    if let secondMono = ccd2.outputImage {
                                        let blend = CIFilter.screenBlendMode()
                                        blend.inputImage = secondMono
                                        blend.backgroundImage = baseMono
                                        
                                        if let blended = blend.outputImage {
                                            toneCurve.inputImage = blended
                                            finalImage = toneCurve.outputImage ?? blended
                                        } else {
                                            finalImage = baseMono
                                        }
                                    } else {
                        finalImage = baseMono
                    }
                } else {
                    // SINGLE EXPOSURE: Curve directly
                    toneCurve.inputImage = baseMono
                    finalImage = toneCurve.outputImage ?? baseMono
                }
                
                let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
                guard let finalData = self.ciContext.jpegRepresentation(
                    of: finalImage,
                    colorSpace: sRGB,
                    options: [(kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption): 0.90]
                ) else { return }
                
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: finalData, options: nil)
                    
                    if let location = location {
                        request.location = location
                    }
                })
            }
        }
}
