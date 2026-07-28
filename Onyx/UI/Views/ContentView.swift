import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            let viewfinderWidth = geometry.size.width - Theme.Layout.viewfinderInset
            let viewfinderHeight = viewfinderWidth * (4.0 / 3.0)
            
            VStack(spacing: 0) {
                TopControlsView(
                    isSettingsOpen: $viewModel.isSettingsOpen,
                    viewModel: viewModel,
                    iconOrientation: viewModel.iconOrientation
                )
                
                ZStack(alignment: .bottom) {
                    ViewfinderView(
                        viewModel: viewModel,
                        geometry: geometry,
                        isActive: !viewModel.isCapturing,
                        iconOrientation: viewModel.iconOrientation
                    )
                    .frame(width: viewfinderWidth, height: viewfinderHeight)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    
                    if viewModel.isSettingsOpen {
                        SettingsDropdownView(
                            selectedMode: $viewModel.processingMode,
                            isOpen: $viewModel.isSettingsOpen
                        )
                        .padding(.horizontal, Theme.Layout.paddingSmall)
                        .padding(.top, Theme.Layout.paddingSmall)
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
                        .padding(.bottom, Theme.Layout.paddingSmall)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                        .zIndex(3)
                    }
                }
                .frame(width: viewfinderWidth, height: viewfinderHeight, alignment: .top)
                
                BottomControlsView(
                    isFlashOn: $viewModel.isFlashOn,
                    cameraPosition: viewModel.cameraPosition,
                    iconOrientation: viewModel.iconOrientation,
                    onCameraPositionToggle: { viewModel.toggleCameraPosition() },
                    onShutterPress: { viewModel.capturePhoto() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.Color.background.edgesIgnoringSafeArea(.all))
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
        .onCameraCaptureEvent { event in
            if event.phase == .ended {
                viewModel.capturePhoto()
            }
        }
    }
}
