import CoreImage
import Photos
import CoreLocation
import AVFoundation
import UIKit
import UniformTypeIdentifiers

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
                return availableBytes > 500_000_000
            }
        } catch {
            return true
        }
        return true
    }
    
    // TEMPORARY DNG BENCHMARK PIPELINE
    func processAndSave(photoData: Data, location: CLLocation?, context: CIContext, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType, iso: Float, ev: Float) async throws {
        guard hasSufficientStorage() else { throw ProcessorError.insufficientStorage }
        
        let backgroundTaskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "com.onyx.PhotoProcessing") { }
        }
        
        defer {
            Task { @MainActor in UIApplication.shared.endBackgroundTask(backgroundTaskID) }
        }
        
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return }
        
        // Generate a strict sequential ID
        let counter = UserDefaults.standard.integer(forKey: "OnyxPhotoCounter") + 1
        UserDefaults.standard.set(counter, forKey: "OnyxPhotoCounter")
        let shortID = String(format: "%04d", counter)
        
        // Format EV String
        let evString = ev > 0 ? "+\(ev)" : (ev == 0.0 ? "0.0" : "\(ev)")
        
        // Hardcoded to Benchmark format while we bypass the JPEG render
        let fileName = "OnyxBenchmark_\(shortID)_EV\(evString).dng"
        
        do {
            let album = try await getOrCreateOnyxAlbum()
            try await PHPhotoLibrary.shared().performChanges {
                let assetRequest = PHAssetCreationRequest.forAsset()
                
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = "com.adobe.raw-image"
                options.originalFilename = fileName
                
                assetRequest.addResource(with: .photo, data: photoData, options: options)
                if let location = location { assetRequest.location = location }
                
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset else { return }
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                albumChangeRequest?.addAssets([assetPlaceholder] as NSArray)
            }
        } catch {
            print("Failed to save DNG photo to Onyx album: \(error)")
        }
    }
}
