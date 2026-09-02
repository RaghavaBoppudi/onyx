import Photos
import UIKit

@MainActor
@Observable
final class RecentPhotoWatcher: NSObject, PHPhotoLibraryChangeObserver {

    private(set) var thumbnail: UIImage?
    private(set) var assetIdentifier: String?

    private var fetchResult: PHFetchResult<PHAsset>?
    private var isRegistered = false
    private let imageManager = PHImageManager.default()
    private var currentRequestID: PHImageRequestID?

    private static let targetSize = CGSize(width: 160, height: 160)

    func start() async {
        guard await PhotosAuthorization.requestReadWrite() else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: .image, options: options)
        fetchResult = result

        if !isRegistered {
            PHPhotoLibrary.shared().register(self)
            isRegistered = true
        }

        load(from: result)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let fetchResult,
                  let details = changeInstance.changeDetails(for: fetchResult)
            else { return }

            let updated = details.fetchResultAfterChanges
            self.fetchResult = updated
            load(from: updated)
        }
    }

    private func load(from result: PHFetchResult<PHAsset>) {
        guard let asset = result.firstObject else {
            thumbnail = nil
            assetIdentifier = nil
            return
        }

        guard asset.localIdentifier != assetIdentifier else { return }
        assetIdentifier = asset.localIdentifier

        if let currentRequestID {
            imageManager.cancelImageRequest(currentRequestID)
        }

        let identifier = asset.localIdentifier

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        currentRequestID = imageManager.requestImage(
            for: asset,
            targetSize: Self.targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self, let image else { return }
            Task { @MainActor in
                guard self.assetIdentifier == identifier else { return }
                self.thumbnail = image
            }
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}
