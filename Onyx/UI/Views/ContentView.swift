import SwiftUI
import UIKit
import AVFoundation

// MARK: - Reusable Liquid Glass Modifier
private struct LiquidGlassModifier: ViewModifier {
    let isBordered: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isBordered ? 0.4 : 0.0), lineWidth: 0.5)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isBordered ? 0.2 : 0.0), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func liquidGlass(isBordered: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(isBordered: isBordered))
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var iconOrientation: Angle = .zero
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VolumeShutterView(onShutterPress: initiateCapture)
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    ZStack(alignment: .bottom) {
                        viewfinder(geometry: geometry)
                        
                        if viewModel.availableLenses.count > 1 {
                            lensToggleIsland
                                .offset(y: -3)
                        }
                    }
                    .zIndex(1)
                    
                    Spacer().frame(height: 40)
                    bottomControls
                }
            }
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            await viewModel.start()
            updateIconOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            Task { await viewModel.stop() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { newPhase == .active ? await viewModel.start() : await viewModel.stop() }
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
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.scannedURL)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(width: geometry.size.width)
        .clipped()
    }
    
    private var lensToggleIsland: some View {
        let buttonWidth: CGFloat = 64
        let buttonHeight: CGFloat = 48
        let stride = buttonWidth + 12
        let totalCount = viewModel.availableLenses.count
        let currentIndex = viewModel.availableLenses.firstIndex(where: { $0 == viewModel.currentLens }) ?? 0
        let baseOffset = (CGFloat(currentIndex) - (CGFloat(totalCount - 1) / 2.0)) * stride
        
        let stretch = isDragging ? min(abs(dragOffset) * 0.4, 20) : 0
        let dragDirectionOffset = isDragging ? (dragOffset > 0 ? stretch / 2 : -stretch / 2) : 0
        
        return ZStack {
            Capsule()
                .fill(Color.clear)
                .liquidGlass(isBordered: false)
            
            HStack(spacing: 12) {
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
                                viewModel.selectLens(lens)
                            }
                        }
                }
            }
            
            Capsule()
                .fill(Color.clear)
                .liquidGlass(isBordered: true)
                .frame(width: buttonWidth + stretch, height: buttonHeight + 6)
                .offset(x: baseOffset + dragOffset + dragDirectionOffset)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .fixedSize()
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isDragging)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !isDragging {
                        hapticGenerator.prepare()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isDragging = true }
                    }
                    
                    let minDrag = -CGFloat(currentIndex) * stride
                    let maxDrag = CGFloat(totalCount - 1 - currentIndex) * stride
                    
                    let rawTranslation = value.translation.width
                    let clampedTranslation: CGFloat
                    let frictionFactor: CGFloat = 0.12
                    
                    if rawTranslation < minDrag {
                        let excess = rawTranslation - minDrag
                        clampedTranslation = minDrag + (excess * frictionFactor)
                    } else if rawTranslation > maxDrag {
                        let excess = rawTranslation - maxDrag
                        clampedTranslation = maxDrag + (excess * frictionFactor)
                    } else {
                        clampedTranslation = rawTranslation
                    }
                    
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                        dragOffset = clampedTranslation
                    }
                }
                .onEnded { value in
                    let indexOffset = round(value.translation.width / stride)
                    let newIndex = Int(max(0, min(CGFloat(totalCount - 1), CGFloat(currentIndex) + indexOffset)))
                    let targetLens = viewModel.availableLenses[newIndex]
                    
                    let targetBaseOffset = (CGFloat(newIndex) - (CGFloat(totalCount - 1) / 2.0)) * stride
                    let currentVisualPosition = baseOffset + dragOffset
                    
                    if targetLens != viewModel.currentLens {
                        hapticGenerator.impactOccurred()
                        viewModel.selectLens(targetLens)
                    }
                    
                    dragOffset = currentVisualPosition - targetBaseOffset
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
        )
    }
    
    @ViewBuilder
    private func qrPill(for url: URL) -> some View {
        Button(action: {
            hapticGenerator.impactOccurred()
            UIApplication.shared.open(url)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "safari.fill").font(.system(size: 14, weight: .bold))
                Text(url.host ?? url.absoluteString).font(.system(size: 14, weight: .semibold)).lineLimit(1)
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
    
    private var bottomControls: some View {
        ZStack {
            ShutterButton(action: initiateCapture)
                .frame(width: 100)
            
            HStack(spacing: 0) {
                Spacer().frame(maxWidth: .infinity)
                Spacer().frame(width: 100)
                
                ZStack {
                    Button(action: {
                        hapticGenerator.impactOccurred()
                        viewModel.toggleCameraPosition()
                    }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                            .rotationEffect(iconOrientation)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 48)
    }
    
    private func updateIconOrientation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            switch UIDevice.current.orientation {
            case .landscapeLeft: iconOrientation = .degrees(90)
            case .landscapeRight: iconOrientation = .degrees(-90)
            case .portraitUpsideDown: iconOrientation = .degrees(180)
            default: iconOrientation = .degrees(0)
            }
        }
    }
    
    private func initiateCapture() {
        guard !viewModel.isCapturing else { return }
        hapticGenerator.impactOccurred()
        viewModel.capturePhoto()
    }
}
