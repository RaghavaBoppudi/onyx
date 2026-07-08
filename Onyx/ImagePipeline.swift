import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import CoreLocation

struct OnyxFilterPipeline: Sendable {
    nonisolated static func apply(to image: CIImage, isColor: Bool) -> CIImage {
        if isColor {
            // Subtle S-Curve for natural color contrast
            let colorCurve = CIFilter.toneCurve()
            colorCurve.point0 = CGPoint(x: 0.0, y: 0.0)
            colorCurve.point1 = CGPoint(x: 0.25, y: 0.20)
            colorCurve.point2 = CGPoint(x: 0.50, y: 0.50)
            colorCurve.point3 = CGPoint(x: 0.75, y: 0.80)
            colorCurve.point4 = CGPoint(x: 1.0, y: 1.0)
            colorCurve.inputImage = image
            
            return colorCurve.outputImage ?? image
        }
        
        // B&W Orange Filter Matrix (High Red transmission, blocks Blue)
        let monochrome = CIFilter.colorMatrix()
        monochrome.rVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.gVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.bVector = CIVector(x: 0.60, y: 0.40, z: 0.00, w: 0.0)
        monochrome.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        monochrome.inputImage = image
        
        guard let monoImage = monochrome.outputImage else { return image }
        
        // B&W Film Contrast Curve
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
    // nonisolated(unsafe) fixes the Swift 6 strict concurrency static property error
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    nonisolated static func decodeRAW(data: Data) -> CIImage? {
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        
        // Disable all computational photography elements to replicate the flat, natural aesthetic
        rawFilter.luminanceNoiseReductionAmount = 0.0
        rawFilter.colorNoiseReductionAmount = 0.0
        rawFilter.sharpnessAmount = 0.0
        rawFilter.extendedDynamicRangeAmount = 0.0 // Disables Apple's Smart HDR
        rawFilter.localToneMapAmount = 0.0         // Flattens contrast to natural levels
        rawFilter.boostAmount = 0.0
        
        return rawFilter.outputImage
    }
    
    nonisolated static func processAndSave(photoData: Data, location: CLLocation?, isColor: Bool) {
        Task.detached(priority: .userInitiated) {
            guard let baseRaw = decodeRAW(data: photoData) else { return }
            let finalImage = OnyxFilterPipeline.apply(to: baseRaw, isColor: isColor)
            
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
