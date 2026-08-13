import CoreImage
import Photos
import CoreLocation
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import ImageIO

enum ProcessorError: Error {
    case insufficientStorage
    case invalidData
    case renderFailure
}

actor PhotoProcessor {
    static let shared = PhotoProcessor()
    
    private init() {}
    
    private func getOrCreateOnyxAlbum() async throws -> PHAssetCollection {
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        
        var existingAlbum: PHAssetCollection?
        collection.enumerateObjects { album, _, stop in
            if album.localizedTitle == "Onyx" {
                existingAlbum = album
                stop.pointee = true
            }
        }
        
        if let album = existingAlbum { return album }
        
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
    
    func processAndSave(photoData: Data, location: CLLocation?, context: CIContext, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType, iso: Float) async throws {
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
        
        guard let rawFilter = CIRAWFilter(imageData: photoData, identifierHint: nil) else {
            throw ProcessorError.invalidData
        }
        
        // Strip Apple's default computational ISP processing
        rawFilter.localToneMapAmount = 0.0
        rawFilter.luminanceNoiseReductionAmount = 0.0
        rawFilter.colorNoiseReductionAmount = 0.0
        rawFilter.sharpnessAmount = 0.0
        
        guard let rawImage = rawFilter.outputImage else { throw ProcessorError.invalidData }
        
        let pipeline = OnyxFilterPipeline()
        let processedImage = pipeline.apply(to: rawImage, mode: mode, deviceType: deviceType, iso: iso)
        
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 1.0]
        
        guard let colorSpace = rawImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3),
              let jpegData = context.jpegRepresentation(of: processedImage, colorSpace: colorSpace, options: options) else {
            throw ProcessorError.renderFailure
        }
        
        let counter = UserDefaults.standard.integer(forKey: "OnyxPhotoCounter") + 1
        UserDefaults.standard.set(counter, forKey: "OnyxPhotoCounter")
        let shortID = String(format: "%04d", counter)
        
        let fileName = "Onyx_\(shortID).jpg"
        
        do {
            let album = try await getOrCreateOnyxAlbum()
            try await PHPhotoLibrary.shared().performChanges {
                let assetRequest = PHAssetCreationRequest.forAsset()
                
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.jpeg.identifier
                options.originalFilename = fileName
                
                assetRequest.addResource(with: .photo, data: jpegData, options: options)
                if let location = location { assetRequest.location = location }
                
                guard let assetPlaceholder = assetRequest.placeholderForCreatedAsset else { return }
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                albumChangeRequest?.addAssets([assetPlaceholder] as NSArray)
            }
        } catch {
            print("Failed to save JPEG photo to Onyx album: \(error)")
        }
    }
}
