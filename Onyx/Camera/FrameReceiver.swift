import CoreImage

protocol FrameReceiver: AnyObject, Sendable {
    var currentImage: CIImage? { get }
    nonisolated func receive(image: CIImage?)
}
