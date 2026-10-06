import Photos
import UniformTypeIdentifiers
import CoreLocation
import os

nonisolated enum PhotosAuthorization {
    static var hasReadWriteAccess: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    static func requestReadWrite() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }
}

nonisolated struct PhotoLibraryWriter: Sendable {

    func save(heic: Data, location: CLLocation?) async throws {
        guard await PhotosAuthorization.requestReadWrite() else {
            throw CaptureError.photoLibraryAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.heic.identifier
            request.addResource(with: .photo, data: heic, options: options)
            request.location = location
        }

        Log.library.info("Saved HEIC, \(heic.count / 1024) KB, location: \(location != nil)")
    }

    func saveDNG(_ dng: Data, fileName: String, location: CLLocation?) async throws {
        guard await PhotosAuthorization.requestReadWrite() else {
            throw CaptureError.photoLibraryAccessDenied
        }

        let identifier = (UTType("com.adobe.raw-image") ?? .rawImage).identifier

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = identifier
            options.originalFilename = fileName
            request.addResource(with: .photo, data: dng, options: options)
            request.location = location
        }

        Log.library.info("Saved DNG \(fileName, privacy: .public), \(dng.count / 1024) KB, location: \(location != nil)")
    }
}
