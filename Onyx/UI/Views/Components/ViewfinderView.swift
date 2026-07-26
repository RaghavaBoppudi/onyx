import SwiftUI

struct ViewfinderView: View {
    @ObservedObject var viewModel: CameraViewModel
    let geometry: GeometryProxy
    let isActive: Bool
    let iconOrientation: Angle
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            MetalPreview(viewModel: viewModel, isActive: isActive)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if viewModel.isSettingsOpen {
                        withAnimation { viewModel.isSettingsOpen = false }
                    } else {
                        let viewfinderWidth = geometry.size.width - Theme.Layout.viewfinderInset
                        let viewfinderHeight = viewfinderWidth * (4.0 / 3.0)
                        
                        let normalizedX = location.y / viewfinderHeight
                        let normalizedY = 1.0 - (location.x / viewfinderWidth)
                        let normalized = CGPoint(x: normalizedX, y: normalizedY)
                        viewModel.focus(at: location, normalized: normalized)
                    }
                }
            
            if let focusPoint = viewModel.focusPointUI {
                Circle()
                    .fill(Theme.Color.text)
                    .frame(width: Theme.Layout.paddingSmall, height: Theme.Layout.paddingSmall)
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
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(width: geometry.size.width)
        .clipped()
    }
    
    @ViewBuilder
    private func qrPill(for url: URL) -> some View {
        Button(action: {
            hapticGenerator.impactOccurred()
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
