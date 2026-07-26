import CoreImage
import Photos
import CoreLocation
import AVFoundation

struct PhotoProcessor: Sendable {
    private static func getOrCreateOnyxAlbum() async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", "Onyx")
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions)
        
        if let album = collection.firstObject { return album }
        
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
    
    static func processAndSave(photoData: Data, location: CLLocation?, context: CIContext, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType, iso: Float) async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return }

        Task.detached(priority: .userInitiated) {
            let dataToSave: Data
            
            if mode == .auto {
                dataToSave = photoData
            } else {
                guard let rawFilter = CIRAWFilter(imageData: photoData, identifierHint: nil) else { return }
                
                rawFilter.luminanceNoiseReductionAmount = 0.0
                rawFilter.colorNoiseReductionAmount = 0.0
                rawFilter.sharpnessAmount = 0.1
                rawFilter.extendedDynamicRangeAmount = 0.0
                rawFilter.localToneMapAmount = 0.0
                rawFilter.boostAmount = 0.0
                
                guard let baseImage = rawFilter.outputImage else { return }
                
                let finalImage = OnyxFilterPipeline.apply(to: baseImage, mode: mode, deviceType: deviceType, iso: iso)
                
                guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                      let renderedData = context.heifRepresentation(
                          of: finalImage,
                          format: .RGBA8,
                          colorSpace: colorSpace,
                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0]
                      ) else { return }
                
                dataToSave = renderedData
            }
            
            do {
                let album = try await getOrCreateOnyxAlbum()
                try await PHPhotoLibrary.shared().performChanges {
                    let assetRequest = PHAssetCreationRequest.forAsset()
                    assetRequest.addResource(with: .photo, data: dataToSave, options: nil)
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
