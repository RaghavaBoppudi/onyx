//  RecentPhotoWatcher.swift
//  Live-tracks the single most recent photo in the user's library — regardless of
//  which app took it — and keeps a small thumbnail of it in memory.
//
//  This replaces two narrower ideas that came before it: a version that only
//  remembered what Onyx itself last captured (wrong the moment you deleted it, or
//  shot something in the system Camera app instead), and a version that tracked
//  one specific saved identifier purely to notice its own deletion (right for
//  Onyx's own captures, blind to everything else). Both were solving a smaller
//  problem than the one actually wanted: the corner slot should always show
//  whatever photo is currently most recent in the camera roll, full stop. Take
//  five, delete one, the next-most-recent takes its place automatically — because
//  that's what "most recent" means once the deleted one is gone. Nothing here
//  needs to know or care that Onyx exists as a source.
//
//  The empty placeholder shows if and only if the library has zero photos. Every
//  other state — including "Onyx has never taken a picture" — shows something.
//
//  KNOWN LIMITATION, not fixable from here: under Limited Photos access, this can
//  only fetch within the subset the user explicitly granted. If the true most
//  recent photo isn't in that subset, this shows the most recent one that is —
//  that's how Limited Library access is designed to behave everywhere in iOS, not
//  a gap in this code.

import Photos
import UIKit

@MainActor
@Observable
final class RecentPhotoWatcher: NSObject, PHPhotoLibraryChangeObserver {

    /// The current most-recent photo, or `nil` only when the library has none.
    private(set) var thumbnail: UIImage?

    /// Changes when the *tracked asset* changes, not when a better-quality version
    /// of the same thumbnail arrives from progressive delivery. Drives the corner
    /// slot's pop animation — the signal is "a different photo is showing now,"
    /// not "an image finished loading."
    private(set) var assetIdentifier: String?

    private var fetchResult: PHFetchResult<PHAsset>?
    private var isRegistered = false
    // PHImageManager, not PHCachingImageManager: caching is for pre-fetching many
    // assets ahead of a scrolling list, which this never does — it only ever asks
    // for one image at a time. The plain shared manager does the same single
    // request/cancel work for less weight.
    private let imageManager = PHImageManager.default()
    private var currentRequestID: PHImageRequestID?

    /// Pixels, not points — `PHImageManager` wants pixels, and a corner-slot
    /// thumbnail has no need for more than a few dozen regardless of device scale.
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

        guard asset.localIdentifier != assetIdentifier else {
            // Same photo is still the most recent one — nothing actually changed.
            return
        }
        assetIdentifier = asset.localIdentifier

        // A request already in flight for the previous most-recent photo is now
        // answering a question nobody is asking anymore — cancel it rather than
        // let its result land and race the new one.
        if let currentRequestID {
            imageManager.cancelImageRequest(currentRequestID)
        }

        // Captured as a plain String rather than closing over `asset` itself, so
        // the escaping result-handler closure only ever crosses the thread
        // boundary holding an unambiguously Sendable value.
        let identifier = asset.localIdentifier

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true // iCloud-only assets
        options.resizeMode = .fast

        currentRequestID = imageManager.requestImage(
            for: asset,
            targetSize: Self.targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self, let image else { return }
            Task { @MainActor in
                // Belt-and-braces alongside the cancellation above: a request that
                // started before the cancel could still have been mid-flight.
                guard self.assetIdentifier == identifier else { return }
                self.thumbnail = image
            }
        }
    }

    deinit {
        // `deinit` is implicitly nonisolated even on a @MainActor class — it can
        // fire from any context, so it can't read `isRegistered` (main-actor
        // state) to decide whether to unregister. Unregistering an observer that
        // was never registered is a safe no-op, the same way removing an
        // unregistered NotificationCenter observer is, so the check isn't needed.
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
}
