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
        
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.backgroundColor = .black
        
        context.coordinator.configure(with: device, view: mtkView)
        Task { await viewModel.setFrameReceiver(context.coordinator) }
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.isActive = isActive
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, MTKViewDelegate, FrameReceiver, @unchecked Sendable {
        private let currentImageLock = OSAllocatedUnfairLock(initialState: CIImage?(nil))
        private let _isActive = OSAllocatedUnfairLock(initialState: true)
        
        private var commandQueue: MTLCommandQueue?
        private let defaultColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        
        weak var mtkView: MTKView?
        
        var isActive: Bool {
            get { _isActive.withLock { $0 } }
            set { _isActive.withLock { $0 = newValue } }
        }
        
        var currentImage: CIImage? {
            currentImageLock.withLock { $0 }
        }
        
        func configure(with device: MTLDevice, view: MTKView) {
            self.commandQueue = device.makeCommandQueue()
            self.mtkView = view
        }
        
        nonisolated func receive(image: CIImage?) {
            guard _isActive.withLock({ $0 }) else { return }
            currentImageLock.withLock { $0 = image }
            
            DispatchQueue.main.async { [weak self] in
                self?.mtkView?.setNeedsDisplay()
            }
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

                OnyxGlobals.sharedContext.render(image.transformed(by: transform),
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
