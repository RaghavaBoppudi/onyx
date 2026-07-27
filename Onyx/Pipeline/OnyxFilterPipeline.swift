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

    private let monoFilter = CIFilter.colorMatrix()
    private let lutFilter = CIFilter.colorCube()
    private let curveFilter = CIFilter.toneCurve()
    
    nonisolated init() {
        monoFilter.rVector = CIVector(x: 0.65, y: 0.35, z: 0.00, w: 0.0)
        monoFilter.gVector = CIVector(x: 0.65, y: 0.35, z: 0.00, w: 0.0)
        monoFilter.bVector = CIVector(x: 0.65, y: 0.35, z: 0.00, w: 0.0)
        monoFilter.aVector = CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
        
        if let lutData = Self.sharedLUT {
            lutFilter.cubeDimension = lutData.dimension
            lutFilter.cubeData = lutData.data
        }
    }

    nonisolated func apply(to image: CIImage, mode: ProcessingMode, deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera, iso: Float = 100) -> CIImage {
        guard mode != .auto else { return image }
        
        var processingImage = image
        
        if mode == .mono {
            monoFilter.inputImage = processingImage
            processingImage = monoFilter.outputImage ?? processingImage
        }
        
        if mode == .zero {
            if Self.sharedLUT != nil {
                lutFilter.inputImage = processingImage
                processingImage = lutFilter.outputImage ?? processingImage
            }
        }
        
        curveFilter.inputImage = processingImage
        
        let isLowLight = iso > 400
        
        // Restored your exact original S-curves
        if mode == .zero || mode == .mono {
            if deviceType == .builtInUltraWideCamera {
                if isLowLight {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.08)
                    curveFilter.point1 = CGPoint(x: 0.25, y: 0.32)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.58)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.88)
                    curveFilter.point4 = CGPoint(x: 0.95, y: 1.0)
                } else {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.02)
                    curveFilter.point1 = CGPoint(x: 0.22, y: 0.20)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.52)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.88)
                    curveFilter.point4 = CGPoint(x: 0.96, y: 1.0)
                }
            } else if deviceType == .builtInTelephotoCamera {
                if isLowLight {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.05)
                    curveFilter.point1 = CGPoint(x: 0.25, y: 0.30)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.58)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.88)
                    curveFilter.point4 = CGPoint(x: 0.95, y: 1.0)
                } else {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.0)
                    curveFilter.point1 = CGPoint(x: 0.22, y: 0.18)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.52)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.88)
                    curveFilter.point4 = CGPoint(x: 0.96, y: 1.0)
                }
            } else {
                if isLowLight {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.05)
                    curveFilter.point1 = CGPoint(x: 0.25, y: 0.30)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.55)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.85)
                    curveFilter.point4 = CGPoint(x: 0.95, y: 1.0)
                } else {
                    curveFilter.point0 = CGPoint(x: 0.0, y: 0.0)
                    curveFilter.point1 = CGPoint(x: 0.25, y: 0.20)
                    curveFilter.point2 = CGPoint(x: 0.50, y: 0.50)
                    curveFilter.point3 = CGPoint(x: 0.75, y: 0.88)
                    curveFilter.point4 = CGPoint(x: 0.96, y: 1.0)
                }
            }
        }
        
        return curveFilter.outputImage ?? processingImage
    }
}
