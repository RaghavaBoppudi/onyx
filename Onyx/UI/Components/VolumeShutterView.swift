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
        
        context.coordinator.setup(volumeView: volumeView, action: onShutterPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, @unchecked Sendable {
        private var observation: NSKeyValueObservation?
        private var action: (() -> Void)?
        private let audioSession = AVAudioSession.sharedInstance()
        private weak var volumeView: MPVolumeView?
        private weak var volumeSlider: UISlider?
        
        func setup(volumeView: MPVolumeView, action: @escaping () -> Void) {
            self.action = action
            self.volumeView = volumeView
            
            DispatchQueue.global(qos: .userInitiated).async {
                try? self.audioSession.setCategory(.ambient, options: [.mixWithOthers])
                try? self.audioSession.setActive(true)
            }
            
            observation = audioSession.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let self = self,
                      let old = change.oldValue,
                      let new = change.newValue,
                      old != new else { return }
                
                DispatchQueue.main.async {
                    self.action?()
                    
                    if new >= 0.9 || new <= 0.1 {
                        if self.volumeSlider == nil {
                            self.volumeSlider = self.volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider
                        }
                        self.volumeSlider?.setValue(0.5, animated: false)
                    }
                }
            }
            
            NotificationCenter.default.addObserver(self, selector: #selector(suspendAudio), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resumeAudio), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        
        @objc private func suspendAudio() {
            DispatchQueue.global(qos: .userInitiated).async {
                try? self.audioSession.setActive(false)
            }
        }
        
        @objc private func resumeAudio() {
            DispatchQueue.global(qos: .userInitiated).async {
                try? self.audioSession.setActive(true)
            }
        }
        
        deinit {
            observation?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
