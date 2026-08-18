import SwiftUI

struct CompositionGrid: Shape {
    let mode: GridMode
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard mode == .thirds else { return path }
        
        let fractions: [CGFloat] = [1.0/3.0, 2.0/3.0]
        
        for fraction in fractions {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        
        return path
    }
}

struct ViewfinderView: View {
    @ObservedObject var viewModel: CameraViewModel
    let geometry: GeometryProxy
    let isActive: Bool
    let iconOrientation: Angle
    
    var body: some View {
        ZStack(alignment: .bottom) {
            MetalPreview(viewModel: viewModel, isActive: isActive)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if viewModel.isSettingsOpen {
                                withAnimation { viewModel.isSettingsOpen = false }
                                return
                            }
                            
                            let location = value.location
                            let viewfinderWidth = geometry.size.width - (Theme.Layout.viewfinderInset * 2)
                            let viewfinderHeight = viewfinderWidth * Theme.Layout.aspectRatio
                            
                            let safeInset: CGFloat = 30.0
                            guard location.y > safeInset, location.y < viewfinderHeight - safeInset else { return }
                            
                            let normalizedX = location.y / viewfinderHeight
                            let normalizedY = 1.0 - (location.x / viewfinderWidth)
                            let normalized = CGPoint(x: normalizedX, y: normalizedY)
                            viewModel.focus(at: location, normalized: normalized)
                        }
                )
            
            CompositionGrid(mode: viewModel.gridMode)
                .stroke(Theme.Color.text.opacity(0.3), lineWidth: 0.5)
                .allowsHitTesting(false)
            
            if let focusPoint = viewModel.focusPointUI {
                Circle()
                    .stroke(Theme.Color.accent, lineWidth: Theme.Layout.borderWidth * 3)
                    .frame(width: Theme.Layout.focusReticleSize, height: Theme.Layout.focusReticleSize)
                    .position(focusPoint)
                    .animation(.easeOut(duration: 0.2), value: focusPoint)
            }
            
            if let url = viewModel.scannedURL {
                qrPill(for: url)
                    .padding(.bottom, Theme.Layout.qrBottomPadding)
                    .transition(.scale(scale: 0.9))
                    .zIndex(1)
            }
        }
        .animation(Theme.Physics.menuTransition, value: viewModel.scannedURL)
        .aspectRatio(1.0 / Theme.Layout.aspectRatio, contentMode: .fit)
        .frame(width: geometry.size.width - (Theme.Layout.viewfinderInset * 2))
        .clipped()
    }
    
    @ViewBuilder
    private func qrPill(for url: URL) -> some View {
        Button(action: {
            HapticManager.shared.playMedium()
            UIApplication.shared.open(url)
        }) {
            HStack(spacing: Theme.Layout.paddingSmall) {
                Image(systemName: "safari.fill").font(.system(size: Theme.Typography.bodySemibold, weight: .bold))
                Text(url.host ?? url.absoluteString).font(.system(size: Theme.Typography.bodySemibold, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(Theme.Color.background)
            .padding(.horizontal, Theme.Layout.paddingStandard)
            .padding(.vertical, 10)
            .background(Theme.Color.text)
            .clipShape(Capsule())
            .shadow(color: Theme.Color.background.opacity(0.3), radius: 5, x: 0, y: 2)
            .rotationEffect(iconOrientation)
        }
    }
}
