import AVKit
import SwiftUI

struct ShutterButton: View {
    let model: CameraModel

    var body: some View {
        Button {
            Task { await model.capture() }
        } label: {
            Color.clear.frame(width: 78, height: 78)
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!model.acceptsShutter)
        .opacity(model.isShutterDimmed ? 0.4 : 1)
        .accessibilityLabel("Shutter")
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 78, height: 78)
            Circle()
                .fill(Color.onyxAccent)
                .frame(width: 65, height: 65)
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
        }
        .frame(width: 78, height: 78)
        .contentShape(.circle)
        .animation(.smooth(duration: 0.14), value: configuration.isPressed)
        .sensoryFeedback(
            .impact(flexibility: .soft, intensity: 0.55),
            trigger: configuration.isPressed
        ) { _, isPressed in
            isPressed
        }
    }
}

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
