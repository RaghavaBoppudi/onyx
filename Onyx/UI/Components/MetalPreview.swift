import SwiftUI
import MetalKit
import CoreImage
import os

struct MetalPreview: UIViewRepresentable {
    let viewModel: CameraViewModel
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = .black
        
        Task { await viewModel.setFrameReceiver(context.coordinator) }
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, MTKViewDelegate, FrameReceiver, @unchecked Sendable {
        private let currentImageLock = OSAllocatedUnfairLock(initialState: CIImage?(nil))
        let context: CIContext
        let commandQueue: MTLCommandQueue?
        private let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        
        override init() {
            let mtlDevice = MTLCreateSystemDefaultDevice()
            self.context = mtlDevice.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) } ?? CIContext(options: [.cacheIntermediates: false])
            self.commandQueue = mtlDevice?.makeCommandQueue()
            super.init()
        }
        
        nonisolated func receive(image: CIImage?) {
            currentImageLock.withLock { $0 = image }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            autoreleasepool {
                guard let image = currentImageLock.withLock({ $0 }),
                      let drawable = view.currentDrawable,
                      let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

                let bounds = CGRect(origin: .zero, size: view.drawableSize)
                let colorSpace = image.colorSpace ?? defaultColorSpace

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
}
