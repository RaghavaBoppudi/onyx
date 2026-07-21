import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var isFlashing = false
    @State private var iconOrientation: Angle = .zero
    @Environment(\.scenePhase) private var scenePhase
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VolumeShutterView(onShutterPress: initiateCapture)
                
                VStack(spacing: 0) {
                    Spacer()
                    viewfinder(geometry: geometry)
                    Spacer()
                    bottomControls
                }
            }
        }
        .task {
            hapticGenerator.prepare()
            await viewModel.start()
            updateIconOrientation()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task { await viewModel.start() }
            } else if newPhase == .background {
                Task { await viewModel.stop() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateIconOrientation()
        }
    }
    
    private func viewfinder(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            MetalPreview(viewModel: viewModel)
                .blur(radius: viewModel.isSwitchingLens ? 30 : 0)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isSwitchingLens)
            
            Color.black.opacity(isFlashing ? 1.0 : 0)
                .animation(.easeInOut(duration: 0.1), value: isFlashing)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(width: geometry.size.width)
        .clipped()
    }
    
    private var bottomControls: some View {
        HStack(spacing: 0) {
            Button(action: {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
                cycleLens()
            }) {
                Text(viewModel.currentLens?.label ?? "")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(iconOrientation)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
            }
            .opacity(viewModel.availableLenses.count > 1 ? 1.0 : 0.0)
            
            ShutterButton(action: initiateCapture, isCapturing: viewModel.isCapturing)
            
            Button(action: {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
                viewModel.toggleCameraPosition()
            }) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.white)
                    .rotationEffect(iconOrientation)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 48)
    }
    
    private func updateIconOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            switch deviceOrientation {
            case .portrait:
                iconOrientation = .degrees(0)
            case .landscapeLeft:
                iconOrientation = .degrees(90)
            case .landscapeRight:
                iconOrientation = .degrees(-90)
            case .portraitUpsideDown:
                iconOrientation = .degrees(180)
            default:
                break
            }
        }
    }
    
    private func cycleLens() {
        let lenses = viewModel.availableLenses
        guard lenses.count > 1, let current = viewModel.currentLens,
              let currentIndex = lenses.firstIndex(of: current) else { return }
        
        let nextIndex = (currentIndex + 1) % lenses.count
        viewModel.selectLens(lenses[nextIndex])
    }
    
    private func initiateCapture() {
        guard !viewModel.isCapturing else { return }
        
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        
        isFlashing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFlashing = false }
        viewModel.capturePhoto()
    }
}
