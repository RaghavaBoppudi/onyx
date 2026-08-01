import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    private let uiHaptic = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        GeometryReader { geometry in
            let viewfinderWidth = geometry.size.width - (Theme.Layout.viewfinderInset * 2)
            let viewfinderHeight = viewfinderWidth * Theme.Layout.aspectRatio
            
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    
                    ViewfinderView(
                        viewModel: viewModel,
                        geometry: geometry,
                        isActive: !viewModel.isCapturing,
                        iconOrientation: viewModel.iconOrientation
                    )
                    .frame(width: viewfinderWidth, height: viewfinderHeight)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    .padding(.bottom, Theme.Layout.paddingStandard)
                    
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
                    
                    ZStack {
                        HStack(alignment: .center) {
                            HStack(spacing: Theme.Layout.paddingStandard) {
                                Button(action: {
                                    uiHaptic.impactOccurred()
                                    viewModel.toggleGrid()
                                }) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(systemName: "rectangle.split.3x3")
                                            .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                        
                                        if viewModel.gridMode != .none {
                                            Text("\(viewModel.gridMode.rawValue)")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(3)
                                                .background(Circle().fill(Theme.Color.background))
                                                .offset(x: 6, y: 6)
                                        }
                                    }
                                    .foregroundColor(viewModel.gridMode != .none ? Theme.Color.text : Theme.Color.text.opacity(0.5))
                                    .frame(width: 44, height: 44)
                                    .rotationEffect(viewModel.iconOrientation)
                                }
                                
                                Button(action: {
                                    uiHaptic.impactOccurred()
                                    viewModel.isFlashOn.toggle()
                                }) {
                                    Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                        .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                        .foregroundColor(viewModel.isFlashOn ? Theme.Color.text : Theme.Color.text.opacity(0.5))
                                        .frame(width: 44, height: 44)
                                        .rotationEffect(viewModel.iconOrientation)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ShutterButton(action: { viewModel.capturePhoto() })
                                .layoutPriority(1)
                                .disabled(viewModel.isCapturing)
                                .opacity(viewModel.isCapturing ? 0.5 : 1.0)
                            
                            HStack(spacing: Theme.Layout.paddingStandard) {
                                Button(action: {
                                    uiHaptic.impactOccurred()
                                    viewModel.toggleCameraPosition()
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                        .font(.system(size: Theme.Typography.iconStandard, weight: .semibold))
                                        .foregroundColor(Theme.Color.text)
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
                                        .background(Circle().fill(viewModel.isSettingsOpen ? Theme.Color.text : Color.clear))
                                        .rotationEffect(viewModel.iconOrientation)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .opacity(viewModel.isSettingsOpen ? 0 : 1)
                        .allowsHitTesting(!viewModel.isSettingsOpen)
                        .animation(Theme.Physics.menuTransition, value: viewModel.isSettingsOpen)
                        
                        if viewModel.isSettingsOpen {
                            SettingsDropdownView(
                                selectedMode: $viewModel.processingMode,
                                isOpen: $viewModel.isSettingsOpen
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.Layout.viewfinderInset)
                    .padding(.bottom, Theme.Layout.paddingLarge)
                }
                
                if !viewModel.isAuthorized {
                    Theme.Color.background.ignoresSafeArea()
                    
                    VStack(spacing: Theme.Layout.paddingStandard) {
                        Text("ACCESS DENIED")
                            .font(.system(size: Theme.Typography.bodyBold, weight: .bold))
                            .foregroundColor(Theme.Color.text)
                            .tracking(1)
                        
                        Text("Onyx cannot function without camera and gallery access. Enable these permissions in system settings.")
                            .font(.system(size: Theme.Typography.bodySemibold, weight: .regular))
                            .foregroundColor(Theme.Color.text.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, Theme.Layout.paddingSmall)
                        
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("OPEN SETTINGS")
                                .font(.system(size: Theme.Typography.bodyBold, weight: .semibold))
                                .tracking(2)
                                .foregroundColor(Theme.Color.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Capsule().fill(Color.white))
                        }
                    }
                    .padding(Theme.Layout.paddingLarge)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                            .fill(Theme.Color.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                                    .strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: Theme.Layout.borderWidth)
                            )
                    )
                    .padding(.horizontal, Theme.Layout.paddingLarge)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .background(Theme.Color.background.edgesIgnoringSafeArea(.all))
            .alert("STORAGE FULL", isPresented: $viewModel.showStorageAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Onyx requires at least 500MB of free space to safely process and save RAW photographs. Free up space in iOS Settings to continue shooting.")
            }
        }
        .task { await viewModel.start() }
        .onDisappear { Task { await viewModel.stop() } }
    }
}
