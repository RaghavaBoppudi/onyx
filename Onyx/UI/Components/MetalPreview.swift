import SwiftUI
import MetalKit
import CoreImage
import os

struct MetalPreview: UIViewRepresentable {
    let viewModel: CameraViewModel
    let isActive: Bool
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal not supported") }
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.isPaused = !isActive
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = .black
        
        context.coordinator.configure(with: device)
        Task { await viewModel.setFrameReceiver(context.coordinator) }
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = !isActive
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, MTKViewDelegate, FrameReceiver, @unchecked Sendable {
        private let currentImageLock = OSAllocatedUnfairLock(initialState: CIImage?(nil))
        private var context: CIContext?
        private var commandQueue: MTLCommandQueue?
        private let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        
        var currentImage: CIImage? {
            currentImageLock.withLock { $0 }
        }
        
        func configure(with device: MTLDevice) {
            self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
            self.commandQueue = device.makeCommandQueue()
        }
        
        nonisolated func receive(image: CIImage?) {
            currentImageLock.withLock { $0 = image }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            autoreleasepool {
                guard let image = currentImageLock.withLock({ $0 }),
                      let drawable = view.currentDrawable,
                      let commandBuffer = commandQueue?.makeCommandBuffer(),
                      let ciContext = context else { return }

                let bounds = CGRect(origin: .zero, size: view.drawableSize)
                let colorSpace = image.colorSpace ?? defaultColorSpace

                let scaleX = bounds.width / image.extent.width
                let scaleY = bounds.height / image.extent.height
                let scale = max(scaleX, scaleY)
                
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                    .translatedBy(x: (bounds.width - (image.extent.width * scale)) / (2 * scale),
                                  y: (bounds.height - (image.extent.height * scale)) / (2 * scale))

                ciContext.render(image.transformed(by: transform),
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
