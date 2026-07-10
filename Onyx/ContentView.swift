import SwiftUI
import AVFoundation
import MediaPlayer

// MARK: - Global UI Theme
struct Theme {
    static let accent = Color(red: 134/255, green: 134/255, blue: 134/255) // Hex #868686
}

struct ShutterButton: View {
    let action: () -> Void
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: isPressed ? 80 : 88, height: isPressed ? 80 : 88)
            Circle()
                .fill(Theme.accent)
                .frame(width: 72, height: 72)
        }
        .frame(width: 88, height: 88)
        .animation(.spring(response: 0.15, dampingFraction: 0.65), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in
                    action()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
                }
        )
    }
}

// MARK: - Volume Shutter Implementation
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

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    @State private var isFlashing = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VolumeShutterView(onShutterPress: initiateCapture)
            
            VStack(spacing: 0) {
                
                HStack {
                    Spacer()
                    Button(action: {
                        hapticGenerator.impactOccurred()
                        camera.toggleCameraPosition()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(.white)
                            .padding(.trailing, 24)
                            .padding(.top, 12)
                    }
                }
                
                Spacer()
                
                ZStack(alignment: .bottom) {
                    MetalPreview(camera: camera)
                        .blur(radius: camera.isSwitchingLens ? 30 : 0)
                        .animation(.easeInOut(duration: 0.15), value: camera.isSwitchingLens)
                    
                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { location in
                                hapticGenerator.impactOccurred(intensity: 1.0)
                                let nx = location.x / geo.size.width
                                let ny = location.y / geo.size.height
                                camera.lockFocusAndExposure(at: CGPoint(x: nx, y: ny))
                                focusPoint = location
                                showFocusIndicator = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showFocusIndicator = false }
                            }
                    }
                    
                    if showFocusIndicator, let point = focusPoint {
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 50, height: 50)
                            .position(point)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showFocusIndicator)
                    }
                    
                    Color.black.opacity(isFlashing ? 1.0 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFlashing)
                }
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 4 / 3)
                .clipped()
                
                VStack(spacing: 24) {
                    if camera.availableLenses.count > 1 {
                        HStack(spacing: 0) {
                            ForEach(camera.availableLenses, id: \.type) { lens in
                                Button(action: { camera.selectLens(lens) }) {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(camera.currentLens == lens ? Theme.accent : Color.clear)
                                            .frame(width: 4, height: 4)
                                        
                                        Text(lens.label)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(camera.currentLens == lens ? Theme.accent : Color.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 40)
                    } else {
                        Color.clear.frame(height: 24)
                    }
                    
                    ShutterButton(action: initiateCapture)
                }
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
        }
        .onDisappear {
            if camera.session.isRunning {
                DispatchQueue.global(qos: .background).async {
                    camera.session.stopRunning()
                }
            }
        }
    }
    
    private func initiateCapture() {
        hapticGenerator.impactOccurred()
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFlashing = false }
        camera.capturePhoto()
    }
}
