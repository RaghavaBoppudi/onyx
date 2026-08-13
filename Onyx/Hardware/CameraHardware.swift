import AVFoundation

struct CameraHardware: Sendable {
    nonisolated static func availableLenses(for position: AVCaptureDevice.Position) -> [Lens] {
        // 1. Prioritize multi-camera virtual devices to map optical zoom factors accurately
        let virtualDeviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera
        ]
        
        var virtualDevice: AVCaptureDevice?
        for type in virtualDeviceTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                virtualDevice = device
                break
            }
        }
        
        // 2. Extract Apple's calibrated optical switchover thresholds
        if let vDevice = virtualDevice {
            let physicalDevices = vDevice.constituentDevices
            let switchOverFactors = vDevice.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            
            var nativeZoomFactors: [Double] = [1.0]
            nativeZoomFactors.append(contentsOf: switchOverFactors)
            
            guard let wideAngleIndex = physicalDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) else {
                return []
            }
            let wideAngleNativeZoom = nativeZoomFactors[wideAngleIndex]
            
            var lenses: [Lens] = []
            for (index, device) in physicalDevices.enumerated() {
                let relativeZoom = nativeZoomFactors[index] / wideAngleNativeZoom
                
                let label: String
                if relativeZoom < 1.0 {
                    label = "0.5x"
                } else {
                    let isInteger = floor(relativeZoom) == relativeZoom
                    label = isInteger ? String(format: "%.0fx", relativeZoom) : String(format: "%.1fx", relativeZoom)
                }
                
                let eqFocalLength = Float(relativeZoom * 24.0)
                
                lenses.append(Lens(
                    type: device.deviceType,
                    position: position,
                    label: label,
                    equivalentFocalLength: eqFocalLength
                ))
            }
            return lenses.sorted { $0.equivalentFocalLength < $1.equivalentFocalLength }
        }
        
        // 3. Fallback for sensors that do not cluster into a virtual device (e.g., Front cameras)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: position
        )
        
        var lenses: [Lens] = []
        
        for device in discoverySession.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lenses.append(Lens(type: device.deviceType, position: position, label: "0.5x", equivalentFocalLength: 13.0))
            case .builtInWideAngleCamera:
                lenses.append(Lens(type: device.deviceType, position: position, label: "1x", equivalentFocalLength: 24.0))
            case .builtInTelephotoCamera:
                lenses.append(Lens(type: device.deviceType, position: position, label: "2x", equivalentFocalLength: 52.0))
            case .builtInTrueDepthCamera:
                if !lenses.contains(where: { $0.label == "1x" }) {
                    lenses.append(Lens(type: device.deviceType, position: position, label: "1x", equivalentFocalLength: 24.0))
                }
            default:
                break
            }
        }
        
        return lenses.sorted { $0.equivalentFocalLength < $1.equivalentFocalLength }
    }
}
