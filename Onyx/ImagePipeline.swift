import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import CoreLocation
import ImageIO

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
        // Shadows and lower mids remain unchanged
        curve.point0 = CGPoint(x: 0.0, y: 0.02)
        curve.point1 = CGPoint(x: 0.25, y: 0.14)
        curve.point2 = CGPoint(x: 0.50, y: 0.45)
        
        // The Filmic Shoulder: Compress highlights and lower the peak white point
        curve.point3 = CGPoint(x: 0.75, y: 0.65)
        curve.point4 = CGPoint(x: 1.0, y: 0.82)
        
        curve.inputImage = monoImage
        
        return curve.outputImage ?? monoImage
    }
}

struct PhotoProcessor: Sendable {
    
    nonisolated static func decodeRAW(data: Data) -> CIImage? {
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        rawFilter.luminanceNoiseReductionAmount = 0.0
        rawFilter.colorNoiseReductionAmount = 0.0
        rawFilter.sharpnessAmount = 0.0
        rawFilter.extendedDynamicRangeAmount = 0.0
        rawFilter.localToneMapAmount = 0.0
        rawFilter.boostAmount = 0.0
        return rawFilter.outputImage
    }
    
    nonisolated private static func getOrCreateOnyxAlbum() async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", "Onyx")
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions)
        
        if let album = collection.firstObject {
            return album
        }
        
        var albumPlaceholder: String?
        try await PHPhotoLibrary.shared().performChanges {
            let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "Onyx")
            albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection.localIdentifier
        }
        
        guard let identifier = albumPlaceholder,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw NSError(domain: "com.onyx.camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve Onyx album"])
        }
        
        return album
    }
    
    nonisolated static func processAndSave(photoData: Data, location: CLLocation?, context: CIContext) {
        Task.detached(priority: .userInitiated) {
            guard let baseRaw = decodeRAW(data: photoData) else { return }
            
            let finalImage = OnyxFilterPipeline.apply(to: baseRaw)
            
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let finalData = context.jpegRepresentation(
                      of: finalImage,
                      colorSpace: colorSpace,
                      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
                  ) else { return }
            
            do {
                let album = try await getOrCreateOnyxAlbum()
                
                try await PHPhotoLibrary.shared().performChanges {
                    let assetRequest = PHAssetCreationRequest.forAsset()
                    assetRequest.addResource(with: .photo, data: finalData, options: nil)
                    if let location = location { assetRequest.location = location }
                    
                    guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset else { return }
                    
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    albumChangeRequest?.addAssets([assetPlaceholder] as NSArray)
                }
            } catch {
                print("Failed to save photo to Onyx album: \(error)")
            }
        }
    }
}
