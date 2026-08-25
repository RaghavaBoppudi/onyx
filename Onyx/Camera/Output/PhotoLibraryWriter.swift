//  PhotoLibraryWriter.swift
//  HEIC only. Onyx never writes a DNG — the RAW exists for the duration of one
//  render and is discarded.
//
//  `.readWrite` authorization: Onyx both writes new captures and, via
//  `RecentPhotoWatcher`, reads the library to find whatever photo is currently
//  most recent — including ones it didn't take. That second capability needs read
//  access; `.addOnly` never grants it. `PhotosAuthorization` is shared by both
//  files so the same check isn't duplicated between them.

import Photos
import UniformTypeIdentifiers

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

    func save(heic: Data) async throws {
        guard await PhotosAuthorization.requestReadWrite() else {
            throw CaptureError.photoLibraryAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.heic.identifier
            options.shouldMoveFile = false
            request.addResource(with: .photo, data: heic, options: options)
        }

        Log.library.info("Saved HEIC, \(heic.count / 1024) KB")
    }
}
