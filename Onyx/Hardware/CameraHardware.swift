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
        
        // Fallback for single-camera devices (e.g., iPhone SE or front camera)
        guard let vDevice = virtualDevice else {
            let singleTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera]
            for type in singleTypes {
                if let singleDevice = AVCaptureDevice.default(type, for: .video, position: position) {
                    return [Lens(type: singleDevice.deviceType, position: position, label: "1x", equivalentFocalLength: 24.0)]
                }
            }
            return []
        }
        
        // 2. Extract Apple's calibrated optical switchover thresholds
        let physicalDevices = vDevice.constituentDevices
        let switchOverFactors = vDevice.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
        
        // The first constituent device (widest) always starts at 1.0x native zoom in the virtual device's scale
        var nativeZoomFactors: [Double] = [1.0]
        nativeZoomFactors.append(contentsOf: switchOverFactors)
        
        // 3. Identify the Wide Angle device to use as the 1x anchor baseline
        guard let wideAngleIndex = physicalDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            return []
        }
        let wideAngleNativeZoom = nativeZoomFactors[wideAngleIndex]
        
        // 4. Map out each physical lens dynamically based on its relative ratio to the Wide lens
        var lenses: [Lens] = []
        for (index, device) in physicalDevices.enumerated() {
            let relativeZoom = nativeZoomFactors[index] / wideAngleNativeZoom
            
            let label: String
            if relativeZoom < 1.0 {
                // Apple universally markets the ultra-wide as 0.5x, even if the math is technically ~0.44x
                label = "0.5x"
            } else {
                // Strip the decimal for whole numbers (e.g., "3x" instead of "3.0x"), keep it for fractions (e.g., "2.5x")
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
}
