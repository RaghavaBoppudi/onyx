//  OrientationResolver.swift
//  Turns a horizon-level rotation angle into an EXIF orientation.
//
//  `AVCaptureDevice.RotationCoordinator` already folds in how the sensor is
//  physically mounted, so one code path covers every rear camera in the lineup.
//
//  The result is handed to `CIRAWFilter.orientation`, so the decoder reads the
//  mosaic in the right order and the encoded HEIC is upright with no orientation
//  tag to argue about. This is why there is no DNG metadata patcher: ImageIO cannot
//  write `com.adobe.raw-image`, so stamping a DNG was never going to work. Rendering
//  our own output makes the problem disappear rather than solving it.
//
//  There is no mirroring case. Onyx has no front camera.

import AVFoundation
import ImageIO

enum OrientationResolver {

    static func exifOrientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        let normalised = Int((angle.truncatingRemainder(dividingBy: 360) + 360)
                                .truncatingRemainder(dividingBy: 360).rounded())
        return switch normalised {
        case 0:   .up
        case 90:  .right
        case 180: .down
        default:  .left
        }
    }

    /// Degrees to counter-rotate chrome glyphs while the UI stays portrait.
    /// A scalar, not a SwiftUI `Angle` — nothing in Camera/ knows SwiftUI exists.
    static func glyphRotationDegrees(forRotationAngle angle: CGFloat) -> Double {
        Double(angle) - 90
    }
}
