import CoreLocation
import os

final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let _currentLocation = OSAllocatedUnfairLock(initialState: CLLocation?(nil))
    
    var currentLocation: CLLocation? {
        get { _currentLocation.withLock { $0 } }
        set { _currentLocation.withLock { $0 = newValue } }
    }

    override init() {
        super.init()
        DispatchQueue.main.async {
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyBest
            self.manager.requestWhenInUseAuthorization()
            self.manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
