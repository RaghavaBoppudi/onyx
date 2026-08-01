import CoreImage
import Photos
import CoreLocation
import AVFoundation
import UIKit

enum ProcessorError: Error {
    case insufficientStorage
}

actor PhotoProcessor {
    static let shared = PhotoProcessor()
    
    private init() {}
    
    private func getOrCreateOnyxAlbum() async throws -> PHAssetCollection {
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
    
    private func hasSufficientStorage() -> Bool {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let availableBytes = values.volumeAvailableCapacityForImportantUsage {
                return availableBytes > 500_000_000 // 500 MB hard limit
            }
        } catch {
            return true
        }
        return true
    }
    
    func processAndSave(photoData: Data, location: CLLocation?, context: CIContext, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType, iso: Float) async throws {
        guard hasSufficientStorage() else { throw ProcessorError.insufficientStorage }
        
        let backgroundTaskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "com.onyx.PhotoProcessing") {
                // Task expired
            }
        }
        
        defer {
            Task { @MainActor in UIApplication.shared.endBackgroundTask(backgroundTaskID) }
        }
        
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return }

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
            rawFilter.boostAmount = 1.0
            
            guard let baseImage = rawFilter.outputImage else { return }
            
            let pipeline = OnyxFilterPipeline()
            let finalImage = pipeline.apply(to: baseImage, mode: mode, deviceType: deviceType, iso: iso)
            
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let renderedData = context.jpegRepresentation(
                      of: finalImage,
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
