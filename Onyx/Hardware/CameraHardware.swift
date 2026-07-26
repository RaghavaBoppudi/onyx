import AVFoundation

struct CameraHardware: Sendable {
    static func availableLenses(for position: AVCaptureDevice.Position) -> [Lens] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: position
        )
        
        var lenses: [Lens] = []
        
        for device in discoverySession.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lenses.append(Lens(
                    type: device.deviceType,
                    position: position,
                    label: "0.5x",
                    equivalentFocalLength: 13.0
                ))
                
            case .builtInWideAngleCamera:
                lenses.append(Lens(
                    type: device.deviceType,
                    position: position,
                    label: "1x",
                    equivalentFocalLength: 24.0
                ))
                
            case .builtInTelephotoCamera:
                            let fov = device.activeFormat.videoFieldOfView
                            let label: String
                            let eqFocalLength: Float
                            
                            if fov < 22.0 {
                                label = "5x"
                                eqFocalLength = 120.0
                            } else if fov < 28.0 {
                                label = "4x"
                                eqFocalLength = 100.0
                            } else {
                                label = "3x"
                                eqFocalLength = 77.0
                            }
                            
                            lenses.append(Lens(
                                type: device.deviceType,
                                position: position,
                                label: label,
                                equivalentFocalLength: eqFocalLength
                            ))
                
            default:
                break
            }
        }
        
        // Guarantees UI pills are always ordered from widest to tightest
        return lenses.sorted { $0.equivalentFocalLength < $1.equivalentFocalLength }
    }
}
