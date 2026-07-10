import AVFoundation
import CoreLocation

struct Lens: Equatable {
    let type: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let label: String
}

struct CameraHardware {
    static func availableLenses(for position: AVCaptureDevice.Position) -> [Lens] {
        var discovered: [Lens] = []
        if position == .back {
            if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
                discovered.append(Lens(type: .builtInUltraWideCamera, position: .back, label: "0.5x"))
            }
            if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
                discovered.append(Lens(type: .builtInWideAngleCamera, position: .back, label: "1x"))
            }
            if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
                discovered.append(Lens(type: .builtInTelephotoCamera, position: .back, label: "4x"))
            }
        } else {
            if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
                discovered.append(Lens(type: .builtInWideAngleCamera, position: .front, label: "1x"))
            }
        }
        return discovered
    }
}

class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var currentLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
