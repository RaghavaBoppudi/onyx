import AVFoundation
import CoreImage
import ImageIO
import Testing
@testable import Onyx

struct LookRendererTests {

    private let size = 64

    private func solidJPEG(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let image = CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CIContext().jpegRepresentation(of: image, colorSpace: space, options: [:]))
    }

    private func request(_ mode: CaptureMode) -> CaptureRequest {
        CaptureRequest(
            id: UUID(),
            mode: mode,
            position: .back,
            rotationAngle: 90,
            isPortrait: true,
            flashMode: .off,
            location: nil
        )
    }

    private func centerPixel(of heic: Data) throws -> (r: Int, g: Int, b: Int) {
        let image = try #require(CIImage(data: heic))
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            image,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: size / 2, y: size / 2, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (Int(rgba[0]), Int(rgba[1]), Int(rgba[2]))
    }

    @Test func monoOutputHasNoColour() async throws {
        let shot = RawCapture(data: try solidJPEG(red: 0.9, green: 0.5, blue: 0.1), isRAW: false, orientation: .up)
        let output = try await LookRenderer().render(shot, request: request(.mono))

        let pixel = try centerPixel(of: output.heic)
        #expect(abs(pixel.r - pixel.g) <= 3)
        #expect(abs(pixel.g - pixel.b) <= 3)
    }

    @Test func standardLookKeepsWarmColoursWarm() async throws {
        let shot = RawCapture(data: try solidJPEG(red: 0.9, green: 0.5, blue: 0.1), isRAW: false, orientation: .up)
        let output = try await LookRenderer().render(shot, request: request(.standard))

        let pixel = try centerPixel(of: output.heic)
        #expect(pixel.r > pixel.g && pixel.g > pixel.b)
        #expect(output.usedRAWPath == false)
    }

    @Test func outputKeepsItsDimensions() async throws {
        let shot = RawCapture(data: try solidJPEG(red: 0.4, green: 0.4, blue: 0.4), isRAW: false, orientation: .up)
        let output = try await LookRenderer().render(shot, request: request(.standard))

        let image = try #require(CIImage(data: output.heic))
        #expect(Int(image.extent.width) == size)
        #expect(Int(image.extent.height) == size)
    }

    @Test func savedPhotosCarryOnyxMetadataAndUprightOrientation() async throws {
        let shot = RawCapture(data: try solidJPEG(red: 0.4, green: 0.4, blue: 0.4), isRAW: false, orientation: .up)
        let output = try await LookRenderer().render(shot, request: request(.standard))

        let source = try #require(CGImageSourceCreateWithData(output.heic as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        #expect(tiff?[kCGImagePropertyTIFFSoftware as String] as? String == "Onyx")
        #expect((properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1)
    }
}
