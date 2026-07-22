@preconcurrency import AVFoundation

struct CameraHardware: Sendable {
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
