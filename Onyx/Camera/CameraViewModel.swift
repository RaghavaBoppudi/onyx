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
    
    private let engine = CameraEngine()
    
    func setFrameReceiver(_ receiver: FrameReceiver) async {
        await engine.setFrameReceiver(receiver)
    }
    
    func start() async {
        let authorized = await engine.start()
        guard authorized else {
            // Optional: You can handle the unauthorized state here (e.g., show an alert)
            return
        }
        self.availableLenses = await engine.availableLenses
        self.currentLens = await engine.currentLens
    }
    
    func stop() async {
        await engine.stop()
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
