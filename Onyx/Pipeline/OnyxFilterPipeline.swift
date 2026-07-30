import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import AVFoundation

final class OnyxFilterPipeline: @unchecked Sendable {
    
    private struct LUTData: Sendable {
        let data: Data
        let dimension: Float
    }
    
    private nonisolated static let sharedLUT: LUTData? = {
        guard let url = Bundle.main.url(forResource: "NaturalLUT", withExtension: "cube"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        
        var dimension = 0
        var cubeData = [Float]()
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            if line.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(separator: " ")
                if parts.count == 2, let dim = Int(parts[1]) {
                    dimension = dim
                }
            }
            
            let components = line.split(separator: " ")
            if components.count == 3,
               let r = Float(components[0]),
               let g = Float(components[1]),
               let b = Float(components[2]) {
                cubeData.append(r)
                cubeData.append(g)
                cubeData.append(b)
                cubeData.append(1.0)
            }
        }
        
        guard dimension > 0, cubeData.count == dimension * dimension * dimension * 4 else { return nil }
        
        let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTData(data: data, dimension: Float(dimension))
    }()

    nonisolated init() {}

    nonisolated func apply(to image: CIImage, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera, iso: Float = 100) -> CIImage {
        guard mode != .auto else { return image }
        var processingImage = image

        if mode == .mono {
            processingImage = processingImage.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.35, y: 0.55, z: 0.10, w: 0.0),
                "inputGVector": CIVector(x: 0.35, y: 0.55, z: 0.10, w: 0.0),
                "inputBVector": CIVector(x: 0.35, y: 0.55, z: 0.10, w: 0.0),
                "inputAVector": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
            ])
        }

        if mode == .zero {
            if let lut = Self.sharedLUT {
                processingImage = processingImage.applyingFilter("CIColorCube", parameters: [
                    "inputCubeDimension": lut.dimension,
                    "inputCubeData": lut.data
                ])
            }
        }

        return processingImage.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0.0, y: 0.0),
            "inputPoint1": CIVector(x: 0.25, y: 0.22),
            "inputPoint2": CIVector(x: 0.50, y: 0.50),
            "inputPoint3": CIVector(x: 0.75, y: 0.82),
            "inputPoint4": CIVector(x: 1.0, y: 1.0)
        ])
    }
}
