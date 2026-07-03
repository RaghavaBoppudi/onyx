import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

struct PhotoProcessor {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    func processAndSave(photoData: Data, location: CLLocation?) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rawFilter = CIRAWFilter(imageData: photoData, identifierHint: nil) else { return }
            
            rawFilter.luminanceNoiseReductionAmount = 0.0
            rawFilter.colorNoiseReductionAmount = 0.0
            rawFilter.sharpnessAmount = 0.0
            rawFilter.extendedDynamicRangeAmount = 0.0
            
            guard let currentImage = rawFilter.outputImage else { return }
            
            let mono = CIFilter.colorControls()
            mono.inputImage = currentImage
            mono.saturation = 0.0
            guard let desaturatedImage = mono.outputImage else { return }
            
            let curve = CIFilter.toneCurve()
            curve.inputImage = desaturatedImage
            curve.point0 = CGPoint(x: 0.0, y: 0.02)
            curve.point1 = CGPoint(x: 0.25, y: 0.30)
            curve.point2 = CGPoint(x: 0.5, y: 0.55)
            curve.point3 = CGPoint(x: 0.75, y: 0.80)
            curve.point4 = CGPoint(x: 1.0, y: 0.98)
            
            guard let finalImage = curve.outputImage else { return }
            
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
