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
            guard let baseRaw = self.decodeRAW(data: photoData),
                  let baseMono = baseRaw.applyingMonolithMonochrome() else { return }
            
            var finalImage: CIImage
            
            if let secondaryData = secondaryData,
               let secondRaw = self.decodeRAW(data: secondaryData),
               let secondMono = secondRaw.applyingMonolithMonochrome() {
                
                let blend = CIFilter.screenBlendMode()
                blend.inputImage = secondMono
                blend.backgroundImage = baseMono
                let blended = blend.outputImage ?? baseMono
                
                finalImage = blended.applyingMonolithToneCurve() ?? blended
            } else {
                finalImage = baseMono.applyingMonolithToneCurve() ?? baseMono
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
                if let location = location { request.location = location }
            })
        }
    }
}
