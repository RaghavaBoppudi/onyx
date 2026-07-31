import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    private let uiHaptic = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        GeometryReader { geometry in
            let viewfinderWidth = geometry.size.width - (Theme.Layout.viewfinderInset * 2)
            let viewfinderHeight = viewfinderWidth * Theme.Layout.aspectRatio
            
            VStack(spacing: 0) {
                Spacer()
                
                // Viewfinder Block
                ZStack(alignment: .bottom) {
                    ViewfinderView(
                        viewModel: viewModel,
                        geometry: geometry,
                        isActive: !viewModel.isCapturing,
                        iconOrientation: viewModel.iconOrientation
                    )
                    .frame(width: viewfinderWidth, height: viewfinderHeight)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    
                    if viewModel.availableLenses.count > 1 {
                        LensSelectorView(
                            availableLenses: viewModel.availableLenses,
                            currentLens: viewModel.currentLens,
                            iconOrientation: viewModel.iconOrientation,
                            onSelectLens: { lens in viewModel.selectLens(lens) }
                        )
                        .padding(.bottom, Theme.Layout.paddingStandard)
                        .opacity(viewModel.isSettingsOpen ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isSettingsOpen)
                    }
                }
                .frame(width: viewfinderWidth, height: viewfinderHeight)
                .padding(.bottom, Theme.Layout.paddingLarge)
                
                // Unified Bottom Control Area
                ZStack {
                    // Standard Control Deck
                    HStack(alignment: .center) {
                        HStack(spacing: Theme.Layout.paddingStandard) {
                            Button(action: {
                                uiHaptic.impactOccurred()
                                viewModel.toggleGrid()
                            }) {
                                Image(systemName: "rectangle.split.3x3")
                                    .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                    .foregroundColor(viewModel.gridMode != .none ? Theme.Color.accent : Theme.Color.text)
                                    .frame(width: 44, height: 44)
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                            
                            Button(action: {
                                uiHaptic.impactOccurred()
                                viewModel.isFlashOn.toggle()
                            }) {
                                Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                    .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                    .foregroundColor(viewModel.isFlashOn ? Theme.Color.accent : Theme.Color.text)
                                    .frame(width: 44, height: 44)
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ShutterButton(action: { viewModel.capturePhoto() })
                            .layoutPriority(1)
                        
                        HStack(spacing: Theme.Layout.paddingStandard) {
                            Button(action: {
                                uiHaptic.impactOccurred()
                                viewModel.toggleCameraPosition()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                    .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                    .foregroundColor(viewModel.cameraPosition == .front ? Theme.Color.accent : Theme.Color.text)
                                    .frame(width: 44, height: 44)
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                            
                            Button(action: {
                                uiHaptic.impactOccurred()
                                withAnimation(Theme.Physics.menuTransition) { viewModel.isSettingsOpen.toggle() }
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                    .foregroundColor(viewModel.isSettingsOpen ? Theme.Color.background : Theme.Color.text)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(viewModel.isSettingsOpen ? Theme.Color.accent : Color.clear))
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .opacity(viewModel.isSettingsOpen ? 0 : 1)
                    .allowsHitTesting(!viewModel.isSettingsOpen)
                    .animation(Theme.Physics.menuTransition, value: viewModel.isSettingsOpen)
                    
                    // Settings Panel Overlay
                    if viewModel.isSettingsOpen {
                        SettingsDropdownView(
                            selectedMode: $viewModel.processingMode,
                            isOpen: $viewModel.isSettingsOpen
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Theme.Layout.viewfinderInset)
                
                Spacer()
            }
            .background(Theme.Color.background.edgesIgnoringSafeArea(.all))
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }
}
