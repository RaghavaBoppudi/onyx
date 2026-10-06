import CoreLocation
import Observation
import os

@MainActor
@Observable
final class LocationProvider {

    private static let maximumAge: TimeInterval = 60

    static var isAuthorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    static var isDenied: Bool {
        switch CLLocationManager().authorizationStatus {
        case .denied, .restricted: true
        default: false
        }
    }

    private(set) var latestLocation: CLLocation?
    private(set) var isAccessDenied = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var generation = 0

    var isRunning: Bool { updatesTask != nil }

    var freshLocation: CLLocation? {
        guard let location = latestLocation,
              location.horizontalAccuracy >= 0,
              -location.timestamp.timeIntervalSinceNow <= Self.maximumAge
        else { return nil }
        return location
    }

    func start() {
        guard updatesTask == nil else { return }

        generation += 1
        let current = generation

        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    apply(update)
                }
            } catch {
                Log.capture.warning("Location updates ended: \(error.localizedDescription, privacy: .public)")
            }
            self?.finish(generation: current)
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
        latestLocation = nil
        isAccessDenied = false
    }

    private func finish(generation finished: Int) {
        guard generation == finished else { return }
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    private func apply(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationRestricted {
            latestLocation = nil
            isAccessDenied = true
            return
        }
        isAccessDenied = false
        if let location = update.location {
            latestLocation = location
        }
    }
}
