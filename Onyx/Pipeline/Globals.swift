import CoreImage
import MetalKit

enum OnyxGlobals {
    static let sharedContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .priorityRequestLow: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
}
