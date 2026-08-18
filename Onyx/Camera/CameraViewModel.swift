import SwiftUI
import AVFoundation
import Combine
import CoreImage

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var availableLenses: [Lens] = []
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isCapturing = false
    @Published var isFlashing = false
    @Published var scannedURL: URL?
    @Published var isAuthorized: Bool = true
    @Published var showStorageAlert: Bool = false
    
    @Published var processingMode: ProcessingMode = .zero {
        didSet { setProcessingPipeline(mode: processingMode) }
    }
    @Published var gridMode: GridMode = .none
    
    @Published var isFlashOn: Bool = false
    @Published var isSettingsOpen: Bool = false
    @Published var focusPointUI: CGPoint?
    
    @Published var iconOrientation: Angle = .zero
    
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
            .sink { [weak self] _ in Task { await self?.stop() } }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in Task { await self?.start() } }
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
        
        await engine.setOnFocusLocked { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                if self?.focusPointUI != nil {
                    HapticManager.shared.playMedium()
                }
            }
        }
        
        await engine.setOnStorageError { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.showStorageAlert = true }
        }
        
        let success = await engine.start()
        self.isAuthorized = success
        
        if success {
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
        isSettingsOpen = false
        cameraPosition = cameraPosition == .back ? .front : .back
        
        Task {
            if let newLens = await engine.switchCameraPosition(to: cameraPosition) {
                let newLenses = await engine.availableLenses
                
                await MainActor.run {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.availableLenses = newLenses
                        self.currentLens = newLens
                    }
                }
            }
        }
    }
    
    func selectLens(_ lens: Lens) {
        guard lens != currentLens else { return }
        currentLens = lens
        Task { await engine.selectLens(lens) }
    }
    
    func capturePhoto() {
        guard !isCapturing else { return }
        isSettingsOpen = false
        isCapturing = true
        let flash = isFlashOn
        triggerFlash()
        
        Task {
            await engine.capturePhoto(flashEnabled: flash)
        }
    }
    
    func setProcessingPipeline(mode: ProcessingMode) {
        Task { await engine.setProcessingPipeline(mode: mode) }
    }
    
    func focus(at uiPoint: CGPoint, normalized: CGPoint) {
        focusPointUI = uiPoint
        Task { await engine.setFocus(point: normalized) }
        
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.focusPointUI = nil }
        }
    }
    
    func toggleGrid() {
        gridMode.toggle()
    }
}
