import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            TopControlsView(
                useZeroProcessing: $viewModel.useZeroProcessing,
                iconOrientation: viewModel.iconOrientation,
                onPipelineToggle: { viewModel.togglePipeline() },
                onCameraPositionToggle: { viewModel.toggleCameraPosition() }
            )
            
            ZStack(alignment: .bottom) {
                MetalPreview(viewModel: viewModel, isActive: !viewModel.isCapturing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                
                LensSelectorView(
                    availableLenses: viewModel.availableLenses,
                    currentLens: viewModel.currentLens,
                    iconOrientation: viewModel.iconOrientation,
                    onSelectLens: { lens in viewModel.selectLens(lens) }
                )
                .padding(.bottom, 24)
            }
            .defersSystemGestures(on: .bottom)
            
            BottomControlsView(
                onShutterPress: { viewModel.capturePhoto() }
            )
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task {
                await viewModel.stop()
            }
        }
    }
}
