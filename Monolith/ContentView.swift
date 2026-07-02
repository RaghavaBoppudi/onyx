import SwiftUI
import AVFoundation
import UIKit

// MARK: - Custom Shutter Button
struct ShutterButtonStyle: ButtonStyle {
    private let cloudWhite = Color(red: 240/255, green: 238/255, blue: 233/255)
    
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(configuration.isPressed ? Color(UIColor.darkGray) : cloudWhite)
            .frame(width: 70, height: 70) // Downsized for a minimalist footprint
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var camera = CameraManager()
    
    @State private var isFlashing = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    
    // Exposure drag state variables
    @State private var dragStartBias: Float = -1.0
    @State private var temporaryExposureBias: Float = -1.0
    
    @State private var audioPlayer: AVAudioPlayer?
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let cloudWhite = Color(red: 240/255, green: 238/255, blue: 233/255)
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Top Control Cluster
                HStack {
                    Button(action: {
                        camera.isMonochrome.toggle()
                    }) {
                        Text(camera.isMonochrome ? "mono" : "color")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(camera.isMonochrome ? .gray : cloudWhite)
                            .frame(width: 85, alignment: .leading)
                    }
                    
                    Spacer()
                    
                    if let currentLens = camera.currentLens {
                        Button(action: {
                            camera.cycleLens()
                        }) {
                            Text(currentLens.label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(cloudWhite)
                                .frame(width: 85, alignment: .trailing)
                        }
                    } else {
                        Spacer().frame(width: 85)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Viewfinder & Interaction Layer
                ZStack {
                    CameraPreview(session: camera.session)
                        .saturation(camera.isMonochrome ? 0.0 : 1.0)
                    
                    // Invisible interaction plane for gestures
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Translates vertical swipe distance into EV steps
                                        let delta = Float(-value.translation.height / 100.0)
                                        let newBias = max(-4.0, min(4.0, dragStartBias + delta))
                                        temporaryExposureBias = newBias
                                        camera.setExposureBias(newBias)
                                    }
                                    .onEnded { _ in
                                        dragStartBias = temporaryExposureBias
                                    }
                            )
                            .onTapGesture { location in
                                let normalizedX = location.x / geometry.size.width
                                let normalizedY = location.y / geometry.size.height
                                camera.setFocusAndExposure(at: CGPoint(x: normalizedX, y: normalizedY))
                                
                                focusPoint = location
                                showFocusIndicator = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    showFocusIndicator = false
                                }
                            }
                    }
                    
                    // Hardware-style focus reticle
                    if showFocusIndicator, let point = focusPoint {
                        Circle()
                            .stroke(cloudWhite, lineWidth: 1.5)
                            .frame(width: 50, height: 50)
                            .position(point)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showFocusIndicator)
                    }
                    
                    // Shutter blackout animation
                    Color.black.opacity(isFlashing ? 1.0 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFlashing)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.black)
                
                Spacer()
                
                // Minimalist Bottom Area
                Button(action: {
                    triggerCapture()
                }) {
                    Color.clear
                }
                .buttonStyle(ShutterButtonStyle())
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            setupAudioPlayer()
            dragStartBias = camera.currentExposureBias
            temporaryExposureBias = camera.currentExposureBias
        }
    }
    
    // Preloads the mechanical audio buffer into memory on a background thread
    private func setupAudioPlayer() {
        DispatchQueue.global(qos: .background).async {
            do {
                // Forces the sound to mute when the physical ringer switch is flipped
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {}
            
            guard let url = Bundle.main.url(forResource: "shutter", withExtension: "wav") else { return }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 0.4
                player.prepareToPlay()
                
                DispatchQueue.main.async { self.audioPlayer = player }
            } catch {}
        }
    }
    
    private func playMechanicalShutter() {
        DispatchQueue.global(qos: .userInitiated).async {
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        }
    }
    
    private func triggerCapture() {
        hapticGenerator.impactOccurred()
        playMechanicalShutter()
        
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFlashing = false
        }
        
        camera.capturePhoto()
    }
}
