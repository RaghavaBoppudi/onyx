import CoreImage

protocol FrameReceiver: AnyObject, Sendable {
    nonisolated func receive(image: CIImage?)
}
