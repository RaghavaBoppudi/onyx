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

    static func glyphRotationDegrees(forRotationAngle angle: CGFloat) -> Double {
        Double(angle) - 90
    }
}
