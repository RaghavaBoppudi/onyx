//  Lens.swift
//  A user-selectable optic, and the catalog that discovers them. One file because
//  nothing ever calls `LensCatalog` without immediately using the `Lens` values it
//  returns — the type and the thing that produces it belong together.
//
//  A Lens is one *physical* rear AVCaptureDevice, never virtual: RAW is unavailable
//  on virtual multi-camera devices, and `videoZoomFactor` never reaches the RAW
//  readout. Since the look depends on decoding RAW ourselves, discrete physical
//  lenses are the only correct model. Rear only — the front camera would have meant
//  a crop that can't survive to the decoder and two unrelated hardware mechanisms
//  behind one control; neither earned its place.

import AVFoundation

struct Lens: Identifiable, Hashable, Sendable {
    let id: String
    let deviceType: AVCaptureDevice.DeviceType

    /// Optical factor relative to the wide-angle lens: 0.5 ultra-wide, 1.0 wide,
    /// 2.0 or 4.0 telephoto depending on hardware. Derived, never hardcoded.
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

// MARK: - Catalog

/// Builds the lens list for *this* device at runtime, with zero model-name
/// branching.
///
/// Virtual Device Switch-Over Factors: a virtual device publishes the zoom factors,
/// relative to its widest constituent, at which it hands off to the next lens. A
/// triple camera with constituents [ultraWide, wide, tele] and factors [2, 8] has
/// native factors [1, 2, 8]; normalising by the wide's factor gives [0.5x, 1x, 4x].
/// An iPhone 11 Pro reports [2, 4] and renders 0.5x / 1x / 2x.
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

        // Richest virtual device wins: triple > dual-wide > dual.
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

        // Normalise so the wide-angle lens reads exactly 1x.
        let wideIndex = constituents.firstIndex { $0.deviceType == .builtInWideAngleCamera } ?? 0
        let reference = native[wideIndex]
        guard reference > 0 else { return nil }

        return zip(constituents, native)
            .map { device, factor in
                Lens(id: device.uniqueID, deviceType: device.deviceType, factor: factor / reference)
            }
            .sorted { $0.factor < $1.factor }
    }

    /// Devices with no virtual camera (SE, iPhone 16e, most iPads). Without
    /// published geometry there is nothing to derive from, so fall back to
    /// field-of-view ratios against the wide lens.
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
