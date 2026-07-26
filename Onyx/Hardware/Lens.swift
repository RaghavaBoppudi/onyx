import AVFoundation

struct Lens: Equatable, Sendable {
    let type: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let label: String
    let equivalentFocalLength: Float
}
