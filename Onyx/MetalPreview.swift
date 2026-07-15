import SwiftUI
import MetalKit
import CoreImage

struct MetalPreview: UIViewRepresentable {
    let camera: CameraManager
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.backgroundColor = .black
        camera.frameReceiver = context.coordinator
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(context: camera.ciContext) }
    
    class Coordinator: NSObject, MTKViewDelegate, FrameReceiver, @unchecked Sendable {
        nonisolated(unsafe) private var currentImage: CIImage?
        let context: CIContext
        let commandQueue: MTLCommandQueue?
        nonisolated(unsafe) private weak var view: MTKView?
        private let lock = NSLock()
        
        init(context: CIContext) {
            self.context = context
            self.commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
            super.init()
        }
        
        nonisolated func receive(image: CIImage?) {
            lock.lock()
            currentImage = image
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.view?.setNeedsDisplay() }
        }
        
        // MTKViewDelegate methods access UI elements and must run on the MainActor
        @MainActor
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            lock.lock()
            self.view = view
            lock.unlock()
        }
        
        @MainActor
        func draw(in view: MTKView) {
            lock.lock()
            let image = currentImage
            lock.unlock()
            
            guard let image = image,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            let bounds = CGRect(origin: .zero, size: view.drawableSize)
            let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

            let scaleX = bounds.width / image.extent.width
            let scaleY = bounds.height / image.extent.height
            let scale = max(scaleX, scaleY)
            
            let transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: (bounds.width - (image.extent.width * scale)) / (2 * scale),
                              y: (bounds.height - (image.extent.height * scale)) / (2 * scale))

            context.render(image.transformed(by: transform).clampedToExtent(),
                           to: drawable.texture,
                           commandBuffer: commandBuffer,
                           bounds: bounds,
                           colorSpace: colorSpace)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
