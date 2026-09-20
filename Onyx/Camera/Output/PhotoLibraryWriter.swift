import Photos
import UniformTypeIdentifiers
import CoreLocation

enum PhotosAuthorization {
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

actor PhotoLibraryWriter {

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
}
