import Foundation
import AVFoundation
import CoreImage
import CoreLocation
import Combine
import os

struct WeakReceiverBox { weak var receiver: FrameReceiver? }

final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published var session = AVCaptureSession()
    @Published var availableLenses: [Lens] = CameraHardware.availableLenses(for: .back)
    @Published var currentLens: Lens?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var isSwitchingLens = false
    
    private let _frameReceiver = OSAllocatedUnfairLock(initialState: WeakReceiverBox(receiver: nil))
        nonisolated var frameReceiver: FrameReceiver? {
            get { _frameReceiver.withLock { $0.receiver } }
            set { _frameReceiver.withLock { $0.receiver = newValue } }
        }
    
    let ciContext = MTLCreateSystemDefaultDevice().map {
        CIContext(mtlDevice: $0, options: [.cacheIntermediates: false, .priorityRequestLow: false])
    } ?? CIContext(options: [.cacheIntermediates: false])
    
    internal var videoDeviceInput: AVCaptureDeviceInput?
    internal let videoOutput = AVCaptureVideoDataOutput()
    internal let photoOutput = AVCapturePhotoOutput()
    
    internal let videoQueue = DispatchQueue(label: "com.onyx.videoQueue", qos: .userInteractive)
    internal let sessionQueue = DispatchQueue(label: "com.onyx.sessionQueue", qos: .userInitiated)
    internal let locationProvider = LocationProvider()
    internal let _frameCount = OSAllocatedUnfairLock(initialState: 0)
    internal var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    override init() {
        super.init()
        self.currentLens = availableLenses.first(where: { $0.type == .builtInWideAngleCamera }) ?? availableLenses.first
        sessionQueue.async { [weak self] in self?.setupCamera() }
    }
    
    func stopSession() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }
}
