import AVFoundation

struct Lens: Equatable {
    let type: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let label: String
}

struct CameraHardware {
    static func availableLenses() -> [Lens] {
        var discovered: [Lens] = []
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            discovered.append(Lens(type: .builtInUltraWideCamera, position: .back, label: "0.5x"))
        }
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
            discovered.append(Lens(type: .builtInWideAngleCamera, position: .back, label: "1x"))
        }
        if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
            discovered.append(Lens(type: .builtInTelephotoCamera, position: .back, label: "4x"))
        }
        return discovered
    }
}
