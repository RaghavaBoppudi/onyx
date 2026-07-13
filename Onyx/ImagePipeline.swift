import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import CoreLocation

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
        curve.point3 = CGPoint(x: 0.75, y: 0.75)
        curve.point4 = CGPoint(x: 1.0, y: 0.90)
        curve.inputImage = monoImage
        
        return curve.outputImage ?? monoImage
    }
}

struct PhotoProcessor: Sendable {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    nonisolated static func decodeRAW(data: Data) -> CIImage? {
        // CIRAWFilter automatically reads and applies the hardware EXIF orientation tag.
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        rawFilter.luminanceNoiseReductionAmount = 0.0
        rawFilter.colorNoiseReductionAmount = 0.0
        rawFilter.sharpnessAmount = 0.0
        rawFilter.extendedDynamicRangeAmount = 0.0
        rawFilter.localToneMapAmount = 0.0
        rawFilter.boostAmount = 0.0
        return rawFilter.outputImage
    }
    
    nonisolated static func processAndSave(photoData: Data, location: CLLocation?) {
        Task.detached(priority: .userInitiated) {
            guard let baseRaw = decodeRAW(data: photoData) else { return }
            
            // baseRaw is already upright. Do not apply secondary rotations here.
            let finalImage = OnyxFilterPipeline.apply(to: baseRaw)
            
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let finalData = ciContext.jpegRepresentation(
                      of: finalImage,
                      colorSpace: colorSpace,
                      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
                  ) else { return }
            
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: finalData, options: nil)
                    if let location = location { request.location = location }
                }
            } catch {
                print("Failed to save photo: \(error)")
            }
        }
    }
}
