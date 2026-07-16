import SwiftUI
import MediaPlayer
import AVFoundation

struct VolumeShutterView: UIViewRepresentable {
    var onShutterPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.alpha = 0.001
        view.addSubview(volumeView)
        
        context.coordinator.setup(action: onShutterPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, @unchecked Sendable {
        private var observation: NSKeyValueObservation?
        private var action: (() -> Void)?
        private let audioSession = AVAudioSession.sharedInstance()
        
        func setup(action: @escaping () -> Void) {
            self.action = action
            DispatchQueue.global(qos: .background).async {
                try? self.audioSession.setCategory(.ambient, options: [.mixWithOthers])
                try? self.audioSession.setActive(true)
            }
            observation = audioSession.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                DispatchQueue.main.async { self?.action?() }
            }
        }
        deinit { observation?.invalidate() }
    }
}
