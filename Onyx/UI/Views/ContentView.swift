import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    @State private var isFlashing = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VolumeShutterView(onShutterPress: initiateCapture)
                
                VStack(spacing: 0) {
                    topControls
                    Spacer()
                    viewfinder(geometry: geometry)
                    bottomControls
                }
            }
        }
        .onDisappear {
            if camera.session.isRunning {
                DispatchQueue.global(qos: .background).async { camera.session.stopRunning() }
            }
        }
    }
    
    // MARK: - Subviews
    private var topControls: some View {
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
    }
    
    private func viewfinder(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            MetalPreview(camera: camera)
                .blur(radius: camera.isSwitchingLens ? 30 : 0)
                .animation(.easeInOut(duration: 0.15), value: camera.isSwitchingLens)
            
            Color.clear.contentShape(Rectangle())
                .onTapGesture { location in
                    hapticGenerator.impactOccurred(intensity: 1.0)
                    let nx = location.x / geometry.size.width
                    let ny = location.y / geometry.size.height
                    camera.lockFocusAndExposure(at: CGPoint(x: nx, y: ny))
                    focusPoint = location
                    showFocusIndicator = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showFocusIndicator = false }
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
        .frame(width: geometry.size.width, height: geometry.size.width * 4 / 3)
        .clipped()
    }
    
    private var bottomControls: some View {
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
    
    private func initiateCapture() {
        hapticGenerator.impactOccurred()
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFlashing = false }
        camera.capturePhoto()
    }
}
