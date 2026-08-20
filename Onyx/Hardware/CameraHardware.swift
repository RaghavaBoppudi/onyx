import AVFoundation

struct CameraHardware: Sendable {
    private static let backLensesCache: [Lens] = CameraHardware.discoverLenses(for: .back)
    private static let frontLensesCache: [Lens] = CameraHardware.discoverLenses(for: .front)
    
    nonisolated static func availableLenses(for position: AVCaptureDevice.Position) -> [Lens] {
        return position == .back ? backLensesCache : frontLensesCache
    }
    
    private static func discoverLenses(for position: AVCaptureDevice.Position) -> [Lens] {
        var lenses: [Lens] = []
        
        // 1. Front Camera Software Mapping
        if position == .front {
            if let frontDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                lenses.append(Lens(type: frontDevice.deviceType, position: .front, label: "0.5x", equivalentFocalLength: 24.0, videoZoomFactor: 1.0))
                lenses.append(Lens(type: frontDevice.deviceType, position: .front, label: "1x", equivalentFocalLength: 30.0, videoZoomFactor: 1.3))
            }
            return lenses
        }
        
        // 2. Discover Telephoto Multiplier via Virtual Device Switchover Factors
        var telephotoMultiplier: Double = 2.0
        
        if let tripleCamera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            let factors = tripleCamera.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            if factors.count >= 2 {
                // Switchover 0 is UltraWide to Wide. Switchover 1 is Wide to Telephoto.
                telephotoMultiplier = factors[1] / factors[0]
            }
        } else if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            let factors = dualCamera.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            if let first = factors.first {
                // Switchover 0 is Wide to Telephoto.
                telephotoMultiplier = first
            }
        }
        
        // 3. Map Explicit Physical Devices for RAW Capture
        let physicalDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )
        
        for device in physicalDiscovery.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lenses.append(Lens(type: device.deviceType, position: .back, label: "0.5x", equivalentFocalLength: 13.0, videoZoomFactor: 1.0))
            case .builtInWideAngleCamera:
                lenses.append(Lens(type: device.deviceType, position: .back, label: "1x", equivalentFocalLength: 24.0, videoZoomFactor: 1.0))
            case .builtInTelephotoCamera:
                let isInteger = floor(telephotoMultiplier) == telephotoMultiplier
                let label = isInteger ? String(format: "%.0fx", telephotoMultiplier) : String(format: "%.1fx", telephotoMultiplier)
                let eqFocalLength = Float(telephotoMultiplier * 24.0)
                
                lenses.append(Lens(type: device.deviceType, position: .back, label: label, equivalentFocalLength: eqFocalLength, videoZoomFactor: 1.0))
            default:
                break
            }
        }
        
        // 4. Universal Fallback for Base/Legacy Hardware
        if lenses.isEmpty, let singleDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            lenses.append(Lens(type: singleDevice.deviceType, position: .back, label: "1x", equivalentFocalLength: 24.0, videoZoomFactor: 1.0))
        }
        
        return lenses.sorted { $0.equivalentFocalLength < $1.equivalentFocalLength }
    }
}
