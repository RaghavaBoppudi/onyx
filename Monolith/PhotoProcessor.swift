import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

struct PhotoProcessor {
    // Reusable image context. Prevents massive memory leaks during rapid capture.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    func processAndSave(photoData: Data, isMonochrome: Bool, location: CLLocation?) {
        // Offloads heavy image calculation from the UI thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let rawFilter = CIRAWFilter(imageData: photoData, identifierHint: nil) else { return }
            
            // 1. Destroy Apple's Smart HDR and digital smoothing algorithms
            rawFilter.luminanceNoiseReductionAmount = 0.0
            rawFilter.colorNoiseReductionAmount = 0.0
            rawFilter.sharpnessAmount = 0.0
            rawFilter.extendedDynamicRangeAmount = 0.0
            
            guard var currentImage = rawFilter.outputImage else { return }
            
            // 2. Desaturate if requested via UI toggle
            if isMonochrome {
                let mono = CIFilter.colorControls()
                mono.inputImage = currentImage
                mono.saturation = 0.0
                if let output = mono.outputImage {
                    currentImage = output
                }
            }
            
            // 3. Apply the custom contrast curve to crush shadows and mimic analog film density
            let curve = CIFilter.toneCurve()
            curve.inputImage = currentImage
            curve.point0 = CGPoint(x: 0.0, y: 0.02)    // Anchors pure black, crushing the lowest shadows
            curve.point1 = CGPoint(x: 0.25, y: 0.30)  // Gentle lift to retain shadow texture
            curve.point2 = CGPoint(x: 0.5, y: 0.55)   // Mids to prevent aggressive contrast
            curve.point3 = CGPoint(x: 0.75, y: 0.80)  // Slightly lower highlights for smoother roll-off
            curve.point4 = CGPoint(x: 1.0, y: 0.98)   // Retains the muted white point
            
            guard let finalImage = curve.outputImage else { return }
            
            // 4. Flatten the 14-bit RAW into an 8-bit JPEG, discarding unused HDR headroom
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let finalData = self.ciContext.jpegRepresentation(
                of: finalImage,
                colorSpace: sRGB,
                options: [(kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption): 0.90]
            ) else { return }
            
            // 5. Commit to the iOS camera roll silently with GPS tagging
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
