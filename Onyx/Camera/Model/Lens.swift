import AVFoundation

struct Lens: Identifiable, Hashable, Sendable {
    let id: String
    let deviceType: AVCaptureDevice.DeviceType
    let factor: CGFloat

    var label: String { Lens.format(factor) }

    static func format(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))x"
                                            : String(format: "%.1fx", rounded)
    }

    func resolveDevice() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType], mediaType: .video, position: .back
        ).devices.first
    }
}

enum LensCatalog {

    static func lenses() -> [Lens] {
        if let derived = fromVirtualDevice(), derived.count > 1 { return derived }
        return fromDiscovery()
    }

    private static let virtualTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera
    ]

    private static func fromVirtualDevice() -> [Lens]? {
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: virtualTypes, mediaType: .video, position: .back
        ).devices

        guard let virtual = discovered.max(by: {
            $0.constituentDevices.count < $1.constituentDevices.count
        }) else { return nil }

        let constituents = virtual.constituentDevices
        guard !constituents.isEmpty else { return nil }

        var native: [CGFloat] = [1.0]
        native.append(contentsOf:
            virtual.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) })

        guard native.count == constituents.count else {
            Log.lens.error("Switch-over count \(native.count) != constituents \(constituents.count)")
            return nil
        }

        let wideIndex = constituents.firstIndex { $0.deviceType == .builtInWideAngleCamera } ?? 0
        let reference = native[wideIndex]
        guard reference > 0 else { return nil }

        return zip(constituents, native)
            .map { device, factor in
                Lens(id: device.uniqueID, deviceType: device.deviceType, factor: factor / reference)
            }
            .sorted { $0.factor < $1.factor }
    }

    private static func fromDiscovery() -> [Lens] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back
        ).devices

        guard let wide = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? devices.first else { return [] }
        let wideFOV = Double(wide.activeFormat.videoFieldOfView)

        return devices
            .map { device in
                let fov = Double(device.activeFormat.videoFieldOfView)
                let factor: CGFloat = (fov > 0 && wideFOV > 0)
                    ? CGFloat(tan(wideFOV * .pi / 360) / tan(fov * .pi / 360)) : 1.0
                return Lens(id: device.uniqueID, deviceType: device.deviceType, factor: factor)
            }
            .sorted { $0.factor < $1.factor }
    }
}
