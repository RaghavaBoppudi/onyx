import AVKit
import SwiftUI

struct HardwareShutter: UIViewRepresentable {
    let onPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let interaction = AVCaptureEventInteraction { event in
            if event.phase == .ended { onPress() }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
