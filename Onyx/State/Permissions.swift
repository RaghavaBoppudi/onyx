import AVFoundation
import CoreLocation
import Observation
import Photos

@MainActor
@Observable
final class Permissions: NSObject {

    enum Kind: CaseIterable {
        case camera, photos, location

        var isRequired: Bool { self != .location }
    }

    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var location = CLAuthorizationStatus.notDetermined
    private(set) var isRequesting = false

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var locationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    var requiredGranted: Bool {
        Kind.allCases.filter(\.isRequired).allSatisfy { isGranted($0) }
    }

    func isGranted(_ kind: Kind) -> Bool {
        switch kind {
        case .camera: camera == .authorized
        case .photos: photos == .authorized || photos == .limited
        case .location: location == .authorizedWhenInUse || location == .authorizedAlways
        }
    }

    func isDenied(_ kind: Kind) -> Bool {
        switch kind {
        case .camera: camera == .denied || camera == .restricted
        case .photos: photos == .denied || photos == .restricted
        case .location: location == .denied || location == .restricted
        }
    }

    func refresh() {
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        location = locationManager.authorizationStatus
    }

    func request(_ kind: Kind) async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        switch kind {
        case .camera:
            if camera == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
        case .photos:
            if photos == .notDetermined { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        case .location:
            if location == .notDetermined { await requestLocation() }
        }
        refresh()
    }

    private func requestLocation() async {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

extension Permissions: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        location = manager.authorizationStatus
        guard manager.authorizationStatus != .notDetermined else { return }
        locationContinuation?.resume()
        locationContinuation = nil
    }
}
