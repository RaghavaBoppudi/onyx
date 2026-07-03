import SwiftUI
import MetalKit
import CoreImage

struct MetalPreview: UIViewRepresentable {
    var image: CIImage?
    let context: CIContext
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.backgroundColor = .black
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.image = image
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(context: context)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var image: CIImage?
        let context: CIContext
        let commandQueue: MTLCommandQueue?
        
        init(context: CIContext) {
            self.context = context
            self.commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
            super.init()
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let image = image,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
            
            let bounds = CGRect(origin: .zero, size: view.drawableSize)
            let scaleX = bounds.width / image.extent.width
            let scaleY = bounds.height / image.extent.height
            let scale = max(scaleX, scaleY) // Fill screen
            
            let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let xOffset = (bounds.width - scaledImage.extent.width) / 2
            let yOffset = (bounds.height - scaledImage.extent.height) / 2
            let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
            
            context.render(centeredImage, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
