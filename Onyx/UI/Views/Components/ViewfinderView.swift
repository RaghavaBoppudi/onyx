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
}
