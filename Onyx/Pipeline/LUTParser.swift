import Foundation
import CoreImage

enum LUTError: Error {
    case invalidFormat
    case fileUnreadable
    case filterCreationFailure
}

struct LUTParser {
    static func loadCube(from url: URL) throws -> CIFilter {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var size = 0
        var floatArray = [Float]()
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") {
                continue
            }
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                guard parts.count == 2, let parsedSize = Int(parts[1]) else {
                    throw LUTError.invalidFormat
                }
                size = parsedSize
                // Pre-allocate memory: size^3 coordinates * 4 channels (RGBA)
                floatArray.reserveCapacity(size * size * size * 4)
                continue
            }
            
            let components = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
            if components.count == 3 {
                // Extract RGB and inject strict 1.0 Alpha
                floatArray.append(components[0])
                floatArray.append(components[1])
                floatArray.append(components[2])
                floatArray.append(1.0)
            }
        }
        
        let expectedCount = size * size * size * 4
        guard size > 0, floatArray.count == expectedCount else {
            throw LUTError.invalidFormat
        }
        
        let data = floatArray.withUnsafeBufferPointer { Data(buffer: $0) }
        
        guard let filter = CIFilter(name: "CIColorCube") else {
            throw LUTError.filterCreationFailure
        }
        
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        
        return filter
    }
}
