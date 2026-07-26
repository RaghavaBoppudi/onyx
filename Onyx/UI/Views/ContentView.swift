import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Toolbar - Constrained to its natural height
                TopControlsView(
                    isSettingsOpen: $viewModel.isSettingsOpen,
                    iconOrientation: viewModel.iconOrientation
                )
                
                // Viewfinder - Locked strictly to 4:3 ratio
                ZStack(alignment: .bottom) {
                    ViewfinderView(
                        viewModel: viewModel,
                        geometry: geometry,
                        isActive: !viewModel.isCapturing,
                        iconOrientation: viewModel.iconOrientation
                    )
                    
                    if viewModel.isSettingsOpen {
                        SettingsDropdownView(
                            selectedMode: $viewModel.processingMode,
                            isOpen: $viewModel.isSettingsOpen
                        )
                        .padding(.top, 12)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                        .zIndex(2)
                    }
                    
                    if viewModel.availableLenses.count > 1 {
                        LensSelectorView(
                            availableLenses: viewModel.availableLenses,
                            currentLens: viewModel.currentLens,
                            iconOrientation: viewModel.iconOrientation,
                            onSelectLens: { lens in viewModel.selectLens(lens) }
                        )
                        .padding(.bottom, 20)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * (4.0 / 3.0))
                .clipped()
                
                // Bottom Toolbar - Consumes all remaining vertical space to perfectly center the shutter
                BottomControlsView(
                    isFlashOn: $viewModel.isFlashOn,
                    iconOrientation: viewModel.iconOrientation,
                    onCameraPositionToggle: { viewModel.toggleCameraPosition() },
                    onShutterPress: { viewModel.capturePhoto() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .background(
                VolumeShutterView(onShutterPress: { viewModel.capturePhoto() })
            )
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }
}
