import AVFoundation
import Synchronization

nonisolated enum CameraEvent: Sendable, Equatable {
    case interrupted(Reason)
    case interruptionEnded
    case runtimeError
    case pressureElevated

    enum Reason: Sendable, Equatable {
        case inUseByAnotherApp
        case unavailableInSplitView
        case coolingDown
        case other

        var message: String {
            switch self {
            case .inUseByAnotherApp: String(localized: "Another app is using the camera. On a FaceTime call, turn off your video or end the call to use Onyx.")
            case .unavailableInSplitView: String(localized: "Onyx can't use the camera while another app is on screen. Close the floating video or other app, then try again.")
            case .coolingDown: String(localized: "The camera paused to cool down.")
            case .other: String(localized: "The camera was interrupted.")
            }
        }
    }
}

/// Turns the capture stack's notifications and KVO into one `AsyncStream`.
/// Every stored property is a `Sendable` stream end or a `Mutex`, so the class is safely shared.
nonisolated final class CameraEventMonitor: Sendable {
    let events: AsyncStream<CameraEvent>

    private let continuation: AsyncStream<CameraEvent>.Continuation
    private let sessionTokens = Mutex<[NotificationTokens]>([])
    private let pressureTokens = Mutex<ObservationBag?>(nil)

    init() {
        let pair = AsyncStream.makeStream(of: CameraEvent.self, bufferingPolicy: .bufferingNewest(8))
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        continuation.finish()
    }

    func watch(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        let continuation = continuation

        let tokens: [any NSObjectProtocol] = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { note in
                let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                continuation.yield(.interrupted(CameraEventMonitor.reason(from: raw)))
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
                continuation.yield(.interruptionEnded)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { _ in
                continuation.yield(.runtimeError)
            }
        ]
        let bag = NotificationTokens(tokens)
        sessionTokens.withLock { $0.append(bag) }
    }

    func watchPressure(of devices: [AVCaptureDevice]) {
        let continuation = continuation
        let observations = devices.map { device in
            device.observe(\.systemPressureState, options: [.initial, .new]) { device, _ in
                switch device.systemPressureState.level {
                case .serious, .critical, .shutdown: continuation.yield(.pressureElevated)
                default: break
                }
            }
        }
        let bag = ObservationBag(observations)
        pressureTokens.withLock { $0 = bag }
    }

    private static func reason(from raw: Int?) -> CameraEvent.Reason {
        guard let raw, let reason = AVCaptureSession.InterruptionReason(rawValue: raw) else { return .other }
        switch reason {
        case .videoDeviceInUseByAnotherClient: return .inUseByAnotherApp
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .unavailableInSplitView
        case .videoDeviceNotAvailableDueToSystemPressure: return .coolingDown
        default: return .other
        }
    }
}

/// Tokens are only ever released, never read, so moving them between threads is safe.
private final class NotificationTokens: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]

    init(_ tokens: [any NSObjectProtocol]) {
        self.tokens = tokens
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
