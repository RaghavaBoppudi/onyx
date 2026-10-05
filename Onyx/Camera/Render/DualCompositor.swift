import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

enum DualCompositor {

    static func compose(
        frames: DualFrames,
        rearOrientation: CGImagePropertyOrientation,
        frontOrientation: CGImagePropertyOrientation,
        mirrorsFront: Bool,
        style: DualLayoutStyle
    ) -> CIImage {
        let rear = upright(frames.rear, orientation: rearOrientation)
        let front = upright(frames.front, orientation: frontOrientation, mirrored: mirrorsFront)

        let canvas = rear.extent
        let geometry = DualLayoutGeometry(size: canvas.size, style: style)
        let rearRect = geometry.rear.flipped(inCanvasHeight: canvas.height)
        let frontRect = geometry.front.flipped(inCanvasHeight: canvas.height)

        let background = fill(rear, into: rearRect)
        var foreground = fill(front, into: frontRect)

        if geometry.frontCornerRadius > 0 {
            foreground = rounded(foreground, in: frontRect, radius: geometry.frontCornerRadius)
        }

        return foreground.composited(over: background).cropped(to: canvas)
    }

    private static func upright(
        _ buffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mirrored: Bool = false
    ) -> CIImage {
        let oriented = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let normalized = oriented.transformed(
            by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY)
        )
        return mirrored ? normalized.horizontallyMirrored() : normalized
    }

    private static func fill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translation = CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY
        )
        return scaled.transformed(by: translation).cropped(to: rect)
    }

    private static func rounded(_ image: CIImage, in rect: CGRect, radius: CGFloat) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = .white

        guard let mask = generator.outputImage else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = mask

        return (blend.outputImage ?? image).cropped(to: rect)
    }
}
