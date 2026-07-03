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
            discovered.append(Lens(type: .builtInUltraWideCamera, position: .back, label: "ultra-wide"))
        }
        
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
            discovered.append(Lens(type: .builtInWideAngleCamera, position: .back, label: "wide"))
        }
        
        if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
            discovered.append(Lens(type: .builtInTelephotoCamera, position: .back, label: "tele"))
        }
        
        return discovered
    }
}
