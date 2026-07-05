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
        rawFilter.extendedDynamicRangeAmount = 0.5
        rawFilter.localToneMapAmount = 0.7
        rawFilter.boostAmount = 0.1
        return rawFilter.outputImage
    }
    
    func processAndSave(photoData: Data, location: CLLocation?) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let baseRaw = self.decodeRAW(data: photoData),
                  let baseMono = baseRaw.applyingOnyxMonochrome() else { return }
            
            let finalImage = baseMono.applyingOnyxToneCurve() ?? baseMono
            
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
