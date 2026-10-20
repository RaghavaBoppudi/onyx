import CoreGraphics
import ImageIO
import Testing
@testable import Onyx

struct GeometryTests {

    @Test(arguments: [
        (CGFloat(0), CGImagePropertyOrientation.up),
        (90, .right),
        (180, .down),
        (270, .left),
        (450, .right),
        (-90, .left)
    ])
    func rotationAnglesMapToOrientations(angle: CGFloat, expected: CGImagePropertyOrientation) {
        #expect(CGImagePropertyOrientation(rotationAngle: angle) == expected)
    }

    @Test func compactSizesUsePictureInPictureAndLargeOnesSplit() {
        #expect(DualLayoutStyle.resolve(for: CGSize(width: 390, height: 844)) == .pictureInPicture)
        #expect(DualLayoutStyle.resolve(for: CGSize(width: 834, height: 1194)) == .split)
    }

    @Test func pictureInPictureInsetStaysInsideTheCanvas() {
        let size = CGSize(width: 390, height: 520)
        let geometry = DualLayoutGeometry(size: size, style: .pictureInPicture)
        let canvas = CGRect(origin: .zero, size: size)

        #expect(geometry.rear == canvas)
        #expect(canvas.contains(geometry.front))
        #expect(geometry.frontCornerRadius > 0)
    }

    @Test func splitHalvesTileTheCanvasWithoutOverlap() {
        let size = CGSize(width: 600, height: 900)
        let geometry = DualLayoutGeometry(size: size, style: .split)

        #expect(geometry.front.height == size.height / 2)
        #expect(geometry.rear.height == size.height / 2)
        #expect(geometry.front.intersection(geometry.rear).height == 0)
        #expect(geometry.front.union(geometry.rear) == CGRect(origin: .zero, size: size))
    }

    @Test func flippedRectsMirrorAcrossTheCanvasHeight() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let flipped = rect.flipped(inCanvasHeight: 200)
        #expect(flipped == CGRect(x: 10, y: 140, width: 30, height: 40))
    }

    @Test func frontRotationAnglesStayNormalised() {
        #expect(FrontCameraPipeline.photoRotationAngle(reference: 90) == 0)
        #expect(FrontCameraPipeline.photoRotationAngle(reference: 0) == 270)
        #expect(FrontCameraPipeline.dualRotationAngle(device: 270) == 0)
    }
}
