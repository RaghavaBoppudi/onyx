import SwiftUI
import Metal
import QuartzCore
import CoreImage
import os

class MetalVideoView: UIView {
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    
    override class var layerClass: AnyClass { CAMetalLayer.self }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        metalLayer.device = device
        metalLayer.framebufferOnly = false
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.isOpaque = true
        metalLayer.allowsNextDrawableTimeout = true
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

struct MetalPreview: UIViewRepresentable {
    let viewModel: CameraViewModel
    let isActive: Bool
    
    func makeUIView(context: Context) -> MetalVideoView {
        let view = MetalVideoView()
        context.coordinator.configure(with: view.metalLayer)
        Task { await viewModel.setFrameReceiver(context.coordinator) }
        return view
    }
    
    func updateUIView(_ uiView: MetalVideoView, context: Context) {
        context.coordinator.isActive = isActive
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, FrameReceiver, @unchecked Sendable {
        private let _isActive = OSAllocatedUnfairLock(initialState: true)
        private var commandQueue: MTLCommandQueue?
        
        private let previewContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.cacheIntermediates: false, .priorityRequestLow: true])
        private let defaultColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        
        weak var metalLayer: CAMetalLayer?
        
        var isActive: Bool {
            get { _isActive.withLock { $0 } }
            set { _isActive.withLock { $0 = newValue } }
        }
        
        var currentImage: CIImage? { return nil }
        
        func configure(with layer: CAMetalLayer) {
            self.metalLayer = layer
            self.commandQueue = layer.device?.makeCommandQueue()
        }
        
        nonisolated func receive(image: CIImage?) {
            guard _isActive.withLock({ $0 }), let image = image else { return }
            
            autoreleasepool {
                guard let layer = self.metalLayer,
                      let drawable = layer.nextDrawable(),
                      let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

                let bounds = CGRect(origin: .zero, size: layer.drawableSize)
                guard bounds.width > 0, bounds.height > 0 else { return }
                
                let colorSpace = image.colorSpace ?? defaultColorSpace

                let scaleX = bounds.width / image.extent.width
                let scaleY = bounds.height / image.extent.height
                let scale = max(scaleX, scaleY)
                
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                    .translatedBy(x: (bounds.width - (image.extent.width * scale)) / (2 * scale),
                                  y: (bounds.height - (image.extent.height * scale)) / (2 * scale))

                self.previewContext.render(image.transformed(by: transform),
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
