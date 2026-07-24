import SwiftUI
import AVFoundation
import Combine

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isSwitchingLens = false
    @Published var isCapturing = false
    @Published var isFlashing = false
    @Published var scannedURL: URL?
    
    // UI State defaults to Zero processing
    @Published var useZeroProcessing: Bool = true
    @Published var iconOrientation: Angle = .zero
    
    private let engine = CameraEngine()
    private var qrClearTask: Task<Void, Never>?
    
    func setFrameReceiver(_ receiver: FrameReceiver) async {
        await engine.setFrameReceiver(receiver)
    }
    
    func start() async {
        // Sync the engine's state with the ViewModel's default on launch
        await engine.setProcessingPipeline(isZeroProcessed: self.useZeroProcessing)
        
        await engine.setOnCapture { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.triggerFlash() }
        }
        
        await engine.setOnQRCodeScanned { @Sendable [weak self] stringValue in
            Task { @MainActor [weak self] in self?.processQRCode(stringValue) }
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
        isSwitchingLens = true
        cameraPosition = cameraPosition == .back ? .front : .back
        
        Task {
            if let newLens = await engine.switchCameraPosition(to: cameraPosition) {
                currentLens = newLens
                availableLenses = await engine.availableLenses
            }
            isSwitchingLens = false
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
        
        Task.detached(priority: .userInitiated) { [engine] in
            await engine.capturePhoto()
        }
        
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            isCapturing = false
        }
    }
    
    func setProcessingPipeline(isZeroProcessed: Bool) {
        Task {
            await engine.setProcessingPipeline(isZeroProcessed: isZeroProcessed)
        }
    }
    
    func togglePipeline() {
        setProcessingPipeline(isZeroProcessed: useZeroProcessing)
    }
}
