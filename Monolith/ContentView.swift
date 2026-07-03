import SwiftUI
import AVFoundation
import UIKit
import CoreMotion
import Combine

class MotionManager: ObservableObject {
    private let manager = CMMotionManager()
    @Published var isLevel = false
    @Published var rollOpacity: Double = 0.0
    
    init() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 30.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                let deviation = abs(data.attitude.roll)
                
                var opacity = 1.0 - (deviation * 15.0)
                if opacity < 0 { opacity = 0 }
                
                self?.isLevel = deviation < 0.015
                self?.rollOpacity = opacity
            }
        }
    }
}

struct ShutterButtonStyle: ButtonStyle {
    private let cloudWhite = Color(red: 240/255, green: 238/255, blue: 233/255)
    
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(configuration.isPressed ? Color(UIColor.darkGray) : cloudWhite)
            .frame(width: 70, height: 70)
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DynamicControlIcon: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .frame(minWidth: 36)
                .background(isActive ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var isManualMode = false
    @State private var activeControl: ManualControl = .none
    
    @State private var timerValue = 0
    @State private var countdownDisplay = 0
    @State private var dragLastY: CGFloat = 0
    @State private var showFloatingReadout = false
    
    @State private var isFlashing = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    
    @State private var audioPlayer: AVAudioPlayer?
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let cloudWhite = Color(red: 240/255, green: 238/255, blue: 233/255)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                ZStack {
                    MetalPreview(image: camera.livePreviewImage, context: camera.ciContext)
                    
                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 15)
                                    .onChanged { value in
                                        guard isManualMode, activeControl != .none, activeControl != .timer else { return }
                                        if dragLastY == 0 { dragLastY = value.location.y }
                                        let delta = Float(dragLastY - value.location.y)
                                        dragLastY = value.location.y
                                        showFloatingReadout = true
                                        camera.adjust(control: activeControl, delta: delta)
                                    }
                                    .onEnded { _ in
                                        dragLastY = 0
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            if dragLastY == 0 { showFloatingReadout = false }
                                        }
                                    }
                            )
                            .onTapGesture { location in
                                guard !isManualMode else { return }
                                let nx = location.x / geo.size.width
                                let ny = location.y / geo.size.height
                                camera.setFocusAndExposure(at: CGPoint(x: nx, y: ny))
                                
                                focusPoint = location
                                showFocusIndicator = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showFocusIndicator = false }
                            }
                    }
                    
                    if isManualMode { GridOverlay() }
                    
                    if showFocusIndicator, let point = focusPoint, !isManualMode {
                        Circle()
                            .stroke(cloudWhite, lineWidth: 1.5)
                            .frame(width: 50, height: 50)
                            .position(point)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showFocusIndicator)
                    }
                    
                    if countdownDisplay > 0 {
                        Text("\(countdownDisplay)")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 4)
                    } else if isManualMode && activeControl != .none && activeControl != .timer && showFloatingReadout {
                        Text(currentReadoutText())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    
                    Color.black.opacity(isFlashing ? 1.0 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFlashing)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.black)
                
                Spacer()
                
                HStack {
                    DynamicControlIcon(title: "F", isActive: activeControl == .focus) { toggleControl(.focus) }
                    Spacer()
                    DynamicControlIcon(title: shutterLabel(), isActive: activeControl == .shutter) { toggleControl(.shutter) }
                    Spacer()
                    DynamicControlIcon(title: isoLabel(), isActive: activeControl == .iso) { toggleControl(.iso) }
                    Spacer()
                    Button(action: cycleTimer) {
                        Group {
                            if timerValue > 0 {
                                Text("\(timerValue)s")
                            } else {
                                Image(systemName: "timer")
                            }
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(activeControl == .timer || timerValue > 0 ? .black : .white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .frame(minWidth: 36)
                        .background(activeControl == .timer || timerValue > 0 ? Color.white : Color.clear)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(isManualMode ? 1.0 : 0.0)
                
                HStack {
                    if let currentLens = camera.currentLens {
                        Button(currentLens.label) { camera.cycleLens() }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(cloudWhite)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else { Spacer().frame(maxWidth: .infinity) }
                    
                    Button("") { initiateCapture() }
                        .buttonStyle(ShutterButtonStyle())
                        .disabled(countdownDisplay > 0)
                    
                    Button(isManualMode ? "manual" : "auto") {
                        isManualMode.toggle()
                        activeControl = .none
                        if !isManualMode {
                            camera.resetToAuto(control: .focus)
                            camera.resetToAuto(control: .iso)
                        }
                        hapticGenerator.impactOccurred()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(cloudWhite)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear { setupAudioPlayer() }
    }
    
    private func shutterLabel() -> String {
        if camera.isShutterAuto { return "S" }
        let s = camera.currentShutter
        if s >= 1.0 { return String(format: "%.1fs", s) }
        return "1/\(Int(1.0 / s))"
    }
    
    private func isoLabel() -> String {
        if camera.isISOAuto { return "ISO" }
        return "ISO \(Int(camera.currentISO))"
    }
    
    private func currentReadoutText() -> String {
        switch activeControl {
        case .focus: return String(format: "F: %.2f", camera.currentFocus)
        case .iso: return "ISO \(Int(camera.currentISO))"
        case .shutter:
            let s = camera.currentShutter
            if s >= 1.0 { return String(format: "%.1fs", s) }
            return "1/\(Int(1.0 / s))s"
        default: return ""
        }
    }
    
    private func toggleControl(_ target: ManualControl) {
        if activeControl == target {
            activeControl = .none
            camera.resetToAuto(control: target)
        } else {
            activeControl = target
        }
    }
    
    private func cycleTimer() {
        if activeControl == .timer || timerValue > 0 {
            timerValue = timerValue == 0 ? 3 : (timerValue == 3 ? 10 : 0)
            if timerValue == 0 { activeControl = .none } else { activeControl = .timer }
        } else {
            activeControl = .timer
            timerValue = 3
        }
    }
    
    private func setupAudioPlayer() {
        DispatchQueue.global(qos: .background).async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            if let url = Bundle.main.url(forResource: "shutter", withExtension: "wav"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = 0.4
                player.prepareToPlay()
                DispatchQueue.main.async { self.audioPlayer = player }
            }
        }
    }
    
    private func initiateCapture() {
        hapticGenerator.impactOccurred()
        if timerValue > 0 {
            countdownDisplay = timerValue
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                countdownDisplay -= 1
                if countdownDisplay > 0 {
                    hapticGenerator.impactOccurred(intensity: 0.5)
                } else {
                    timer.invalidate()
                    executeCapture()
                }
            }
        } else {
            executeCapture()
        }
    }
    
    private func executeCapture() {
        DispatchQueue.global(qos: .userInitiated).async {
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        }
        
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFlashing = false
        }
        
        camera.capturePhoto()
    }
}

struct GridOverlay: View {
    @StateObject private var motion = MotionManager()
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                path.move(to: CGPoint(x: w/3, y: 0)); path.addLine(to: CGPoint(x: w/3, y: h))
                path.move(to: CGPoint(x: 2*w/3, y: 0)); path.addLine(to: CGPoint(x: 2*w/3, y: h))
                path.move(to: CGPoint(x: 0, y: h/3)); path.addLine(to: CGPoint(x: w, y: h/3))
                path.move(to: CGPoint(x: 0, y: 2*h/3)); path.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            
            Rectangle()
                .fill(motion.isLevel ? Color.white : Color.white.opacity(0.5))
                .frame(width: geo.size.width * 0.4, height: 1.5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(motion.rollOpacity)
        }
    }
}
