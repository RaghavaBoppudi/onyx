import AVFoundation

struct Lens: Equatable {
    let type: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let label: String
}
