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
    
    private let engine = CameraEngine()
    private var qrClearTask: Task<Void, Never>?
    
    func setFrameReceiver(_ receiver: FrameReceiver) async {
        await engine.setFrameReceiver(receiver)
    }
    
    func start() async {
        await engine.setOnCapture { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                self?.triggerFlash()
            }
        }
        
        await engine.setOnQRCodeScanned { @Sendable [weak self] stringValue in
            Task { @MainActor [weak self] in
                self?.processQRCode(stringValue)
            }
        }
        
        let authorized = await engine.start()
        guard authorized else { return }
        self.availableLenses = await engine.availableLenses
        self.currentLens = await engine.currentLens
    }
    
    func stop() async {
        await engine.stop()
    }
    
    private func triggerFlash() {
        isFlashing = true
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            isFlashing = false
        }
    }
    
    private func processQRCode(_ value: String) {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return }
        
        scannedURL = url
        
        qrClearTask?.cancel()
        qrClearTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            scannedURL = nil
        }
    }
    
    func toggleCameraPosition() {
        Task {
            isSwitchingLens = true
            let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
            cameraPosition = newPosition
            if let newLens = await engine.switchCameraPosition(to: newPosition) {
                currentLens = newLens
                availableLenses = await engine.availableLenses
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            isSwitchingLens = false
        }
    }
    
    func selectLens(_ lens: Lens) {
        guard lens != currentLens else { return }
        Task {
            isSwitchingLens = true
            currentLens = lens
            await engine.selectLens(lens)
            try? await Task.sleep(nanoseconds: 150_000_000)
            isSwitchingLens = false
        }
    }
    
    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            await engine.capturePhoto()
            try? await Task.sleep(nanoseconds: 300_000_000)
            isCapturing = false
        }
    }
}
