import CoreImage

class CCDFilter: CIFilter {
    var inputImage: CIImage?
    
    static var kernel: CIColorKernel = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url),
              let kernel = try? CIColorKernel(functionName: "ccd_monochrome", fromMetalLibraryData: data) else {
            fatalError("Failed to load CCDFilter.metal. Ensure -fcikernel flag is set.")
        }
        return kernel
    }()
    
    override var outputImage: CIImage? {
        guard let inputImage = inputImage else { return nil }
        return CCDFilter.kernel.apply(extent: inputImage.extent, arguments: [inputImage])
    }
}
