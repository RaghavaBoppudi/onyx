import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var iconOrientation: Angle = .zero
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var localCurrentLensLabel: String?
    
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
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            hapticGenerator.prepare()
            await viewModel.start()
            localCurrentLensLabel = viewModel.currentLens?.label
            updateIconOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            Task { await viewModel.stop() }
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
            MetalPreview(viewModel: viewModel, isActive: scenePhase == .active)
                .blur(radius: viewModel.isSwitchingLens ? 30 : 0)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isSwitchingLens)
            
            Color.black.opacity(viewModel.isFlashing ? 1.0 : 0)
                .animation(.easeInOut(duration: 0.1), value: viewModel.isFlashing)
            
            if let url = viewModel.scannedURL {
                qrPill(for: url)
                    .padding(.bottom, 80)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(1)
            }
            
            if viewModel.availableLenses.count > 1 {
                lensToggleIsland
                    .padding(.bottom, 16)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.scannedURL)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(width: geometry.size.width)
        .clipped()
    }
    
    private var lensToggleIsland: some View {
        let buttonWidth: CGFloat = 64
        let buttonHeight: CGFloat = 48
        let spacing: CGFloat = 12
        let stride = buttonWidth + spacing
        let totalCount = viewModel.availableLenses.count
        
        let activeLabel = localCurrentLensLabel ?? viewModel.currentLens?.label ?? viewModel.availableLenses.first?.label ?? ""
        let currentIndex = viewModel.availableLenses.firstIndex(where: { $0.label == activeLabel }) ?? 0
        
        let middleIndex = CGFloat(totalCount - 1) / 2.0
        let baseOffset = (CGFloat(currentIndex) - middleIndex) * stride
        
        let stretch = isDragging ? min(abs(dragOffset) * 0.4, 20) : 0
        let indicatorWidth = buttonWidth + stretch
        let dragDirectionOffset = isDragging ? (dragOffset > 0 ? stretch / 2 : -stretch / 2) : 0
        
        return ZStack {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: Capsule())
            } else {
                Capsule()
                    .fill(Color.clear)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            
            HStack(spacing: spacing) {
                ForEach(0..<totalCount, id: \.self) { index in
                    let lens = viewModel.availableLenses[index]
                    Text(lens.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(currentIndex == index ? .white : .white.opacity(0.6))
                        .frame(width: buttonWidth, height: buttonHeight)
                        .contentShape(Rectangle())
                        .rotationEffect(iconOrientation)
                        .onTapGesture {
                            if currentIndex != index {
                                hapticGenerator.impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    localCurrentLensLabel = lens.label
                                }
                                viewModel.selectLens(lens)
                            }
                        }
                }
            }
            
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                    )
                    .frame(width: indicatorWidth, height: buttonHeight)
                    .offset(x: baseOffset + dragOffset + dragDirectionOffset)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                    .allowsHitTesting(false)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: indicatorWidth, height: buttonHeight)
                    .offset(x: baseOffset + dragOffset + dragDirectionOffset)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fixedSize()
        .scaleEffect(isDragging ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isDragging)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !isDragging {
                        hapticGenerator.prepare()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            isDragging = true
                        }
                    }
                    
                    let minDrag = (0 - CGFloat(currentIndex)) * stride
                    let maxDrag = (CGFloat(totalCount - 1) - CGFloat(currentIndex)) * stride
                    let clampedDrag = max(minDrag, min(maxDrag, value.translation.width))
                    
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                        dragOffset = clampedDrag
                    }
                }
                .onEnded { _ in
                    let indexOffset = round(dragOffset / stride)
                    let newIndex = Int(max(0, min(CGFloat(totalCount - 1), CGFloat(currentIndex) + indexOffset)))
                    let targetLens = viewModel.availableLenses[newIndex]
                    
                    let targetLabel = targetLens.label
                    let changed = activeLabel != targetLabel
                    
                    if changed {
                        hapticGenerator.impactOccurred()
                    }
                    
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        if changed {
                            localCurrentLensLabel = targetLabel
                        }
                        dragOffset = 0
                        isDragging = false
                    }
                    
                    if changed {
                        DispatchQueue.main.async {
                            viewModel.selectLens(targetLens)
                        }
                    }
                }
        )
        .onChange(of: viewModel.currentLens) { _, newValue in
            if !isDragging {
                localCurrentLensLabel = newValue?.label
            }
        }
    }
    
    @ViewBuilder
    private func qrPill(for url: URL) -> some View {
        Button(action: {
            hapticGenerator.impactOccurred()
            UIApplication.shared.open(url)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            .rotationEffect(iconOrientation)
        }
    }
    
    private var superModeToggle: some View {
        Button(action: {
            hapticGenerator.impactOccurred()
            viewModel.isSuperModeActive.toggle()
        }) {
            Text(viewModel.isSuperModeActive ? "48MP" : "12MP")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(viewModel.isSuperModeActive ? .black : .white)
                .frame(width: 60)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(viewModel.isSuperModeActive ? Color.white : Color.white.opacity(0.15))
                )
                .rotationEffect(iconOrientation)
        }
    }
    
    private var bottomControls: some View {
        HStack(spacing: 0) {
            Group {
                if viewModel.cameraPosition == .back {
                    superModeToggle
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity)
            
            ShutterButton(action: initiateCapture)
                .frame(width: 88)
            
            Button(action: {
                hapticGenerator.impactOccurred()
                hapticGenerator.prepare()
                viewModel.toggleCameraPosition()
            }) {
                Text(viewModel.cameraPosition == .back ? "FRONT" : "BACK")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 60)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
                    .rotationEffect(iconOrientation)
            }
            .frame(maxWidth: .infinity)
        }
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
    
    private func initiateCapture() {
        guard !viewModel.isCapturing else { return }
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
        viewModel.capturePhoto()
    }
}
