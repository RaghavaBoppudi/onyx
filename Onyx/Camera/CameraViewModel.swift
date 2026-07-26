import SwiftUI
import AVFoundation
import Combine
import CoreImage

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isSwitchingLens = false
    @Published var isCapturing = false
    @Published var isFlashing = false
    @Published var scannedURL: URL?
    
    @Published var processingMode: ProcessingMode = .zero {
        didSet { setProcessingPipeline(mode: processingMode) }
    }
    @Published var isFlashOn: Bool = false
    @Published var isSettingsOpen: Bool = false
    @Published var focusPointUI: CGPoint?
    @Published var iconOrientation: Angle = .zero
    
    @Published var cameraSnapshot: CGImage? = nil
    @Published var flipDegrees: Double = 0.0
    @Published var isFlipping: Bool = false
    
    private let engine = CameraEngine()
    private var qrClearTask: Task<Void, Never>?
    private var focusTimer: Timer?
    private var frameReceiver: FrameReceiver?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { await self?.stop() }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { await self?.start() }
            }
            .store(in: &cancellables)
    }
    
    func setFrameReceiver(_ receiver: FrameReceiver) async {
        self.frameReceiver = receiver
        await engine.setFrameReceiver(receiver)
    }
    
    func start() async {
        await engine.setProcessingPipeline(mode: self.processingMode)
        
        await engine.setOnQRCodeScanned { @Sendable [weak self] stringValue in
            Task { @MainActor [weak self] in self?.processQRCode(stringValue) }
        }
        
        await engine.setOnCaptureComplete { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.isCapturing = false }
        }
        
        if await engine.start() {
            self.availableLenses = await engine.availableLenses
            self.currentLens = await engine.currentLens
        }
    }
    
    func stop() async {
        await engine.stop()
    }
    
    private func triggerFlash() {
        isFlashing = true
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            isFlashing = false
        }
    }
    
    private func processQRCode(_ value: String) {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        scannedURL = url
        
        qrClearTask?.cancel()
        qrClearTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            scannedURL = nil
        }
    }
    
    func toggleCameraPosition() {
        guard !isFlipping, let currentCIImage = frameReceiver?.currentImage else { return }
        
        let context = CIContext(options: [.cacheIntermediates: false])
        cameraSnapshot = context.createCGImage(currentCIImage, from: currentCIImage.extent)
        isFlipping = true
        flipDegrees = 0.0
        isSwitchingLens = true
        
        cameraPosition = cameraPosition == .back ? .front : .back
        
        Task {
            if let newLens = await engine.switchCameraPosition(to: cameraPosition) {
                currentLens = newLens
                availableLenses = await engine.availableLenses
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                cameraSnapshot = nil
                isFlipping = false
                flipDegrees = 0.0
                isSwitchingLens = false
            }
        }
    }
    
    func selectLens(_ lens: Lens) {
        guard lens != currentLens else { return }
        isSwitchingLens = true
        currentLens = lens
        
        Task {
            await engine.selectLens(lens)
            isSwitchingLens = false
        }
    }
    
    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        let flash = isFlashOn
        
        triggerFlash()
        
        Task.detached(priority: .userInitiated) { [engine] in
            await engine.capturePhoto(flashEnabled: flash)
        }
    }
    
    func setProcessingPipeline(mode: ProcessingMode) {
        Task {
            await engine.setProcessingPipeline(mode: mode)
        }
    }
    
    func focus(at uiPoint: CGPoint, normalized: CGPoint) {
        focusPointUI = uiPoint
        
        Task { await engine.setFocus(point: normalized) }
        
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.focusPointUI = nil
        }
    }
}
