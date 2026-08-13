import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import AVFoundation

final class OnyxFilterPipeline: @unchecked Sendable {
    
    private struct LensCalibration: Sendable {
        let saturation: Float
        let whitePoint: CIColor
    }
    
    private let hardwareCalibrations: [AVCaptureDevice.DeviceType: LensCalibration] = [
        .builtInWideAngleCamera: LensCalibration(
            saturation: 1.05,
            whitePoint: CIColor(red: 1.0, green: 0.98, blue: 0.96)
        ),
        .builtInUltraWideCamera: LensCalibration(
            saturation: 1.05,
            whitePoint: CIColor(red: 1.0, green: 1.0, blue: 1.0)
        ),
        .builtInTelephotoCamera: LensCalibration(
            saturation: 1.05,
            whitePoint: CIColor(red: 1.0, green: 1.0, blue: 1.0)
        )
    ]

    nonisolated init() {}

    nonisolated func apply(to image: CIImage, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera, iso: Float = 100) -> CIImage {
        var processingImage = image

        if mode == .mono {
            processingImage = processingImage.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.75, y: 0.25, z: -0.05, w: 0.0),
                "inputGVector": CIVector(x: 0.75, y: 0.25, z: -0.05, w: 0.0),
                "inputBVector": CIVector(x: 0.75, y: 0.25, z: -0.05, w: 0.0),
                "inputAVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
            ])
        }

        if mode == .zero {
            let calibration = hardwareCalibrations[deviceType] ?? hardwareCalibrations[.builtInWideAngleCamera]!
            
            processingImage = processingImage.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": calibration.saturation,
                "inputContrast": 1.0,
                "inputBrightness": 0.0
            ])
            
            processingImage = processingImage.applyingFilter("CIWhitePointAdjust", parameters: [
                "inputColor": calibration.whitePoint
            ])
        }

        // Unified Static Curve
        // Simulates a balanced film response regardless of ISO
        return processingImage.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.0, y: 0.02),  // Slight lift to emulate film base density
            "inputPoint1": CIVector(x: 0.25, y: 0.26), // Smooth shadow transition
            "inputPoint2": CIVector(x: 0.50, y: 0.50), // Linear midtone anchor
            "inputPoint3": CIVector(x: 0.75, y: 0.80), // Slight highlight contrast pop
            "inputPoint4": CIVector(x: 1.0, y: 0.98)   // Highlight roll-off to prevent hard digital clipping
        ])
    }
}
