import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        GeometryReader { geometry in
            let viewfinderWidth = geometry.size.width - (Theme.Layout.viewfinderInset * 2)
            let viewfinderHeight = viewfinderWidth * Theme.Layout.aspectRatio
            
            ZStack {
                Theme.Color.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // TOP BAR
                    HStack {
                        Button(action: {
                            HapticManager.shared.playLight()
                            viewModel.toggleGrid()
                        }) {
                            Image(systemName: "rectangle.split.3x3")
                                .font(.system(size: Theme.Typography.iconLarge, weight: .semibold))
                                .foregroundColor(viewModel.gridMode != .none ? Theme.Color.text : Theme.Color.text.opacity(0.5))
                                .frame(width: 44, height: 44)
                                .rotationEffect(viewModel.iconOrientation)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            HapticManager.shared.playLight()
                            withAnimation(Theme.Physics.menuTransition) { viewModel.isSettingsOpen.toggle() }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: Theme.Typography.iconLarge, weight: .semibold))
                                .foregroundColor(viewModel.isSettingsOpen ? Theme.Color.text : Theme.Color.text.opacity(0.5))
                                .frame(width: 44, height: 44)
                                .rotationEffect(viewModel.iconOrientation)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.paddingLarge)
                    .padding(.vertical, 8)
                    .zIndex(2)
                    
                    // VIEWFINDER CONTAINER
                    ZStack(alignment: .top) {
                        ViewfinderView(
                            viewModel: viewModel,
                            geometry: geometry,
                            isActive: !viewModel.isProcessing,
                            iconOrientation: viewModel.iconOrientation
                        )
                        
                        if viewModel.isSettingsOpen {
                            SettingsDropdownView(isOpen: $viewModel.isSettingsOpen)
                                .padding([.top, .horizontal], 8)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                                    removal: .opacity.animation(.easeOut(duration: 0.15))
                                ))
                                .zIndex(3)
                        }
                    }
                    .frame(width: viewfinderWidth, height: viewfinderHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                            .fill(Color.black)
                            .opacity(viewModel.showFlash ? 1.0 : 0.0)
                    )
                    .zIndex(1)
                    
                    Spacer()
                    
                    // BOTTOM CONTROLS
                    VStack(spacing: Theme.Layout.paddingLarge) {
                        LensSelectorView(
                            availableLenses: viewModel.availableLenses,
                            currentLens: viewModel.currentLens,
                            iconOrientation: viewModel.iconOrientation,
                            onSelectLens: { lens in viewModel.selectLens(lens) }
                        )
                        .opacity(viewModel.availableLenses.count > 1 ? 1.0 : 0.0)
                        
                        HStack(alignment: .center, spacing: 0) {
                            Button(action: {
                                HapticManager.shared.playLight()
                                viewModel.isFlashOn.toggle()
                            }) {
                                Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                    .font(.system(size: Theme.Typography.iconLarge, weight: .semibold))
                                    .foregroundColor(viewModel.isFlashOn ? Theme.Color.text : Theme.Color.text.opacity(0.5))
                                    .frame(width: 56, height: 56)
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                            .frame(maxWidth: .infinity)
                            
                            ShutterButton(isProcessing: viewModel.isProcessing, action: { viewModel.capturePhoto() })
                                .layoutPriority(1)
                            
                            Button(action: {
                                HapticManager.shared.playLight()
                                viewModel.toggleCameraPosition()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                    .font(.system(size: Theme.Typography.iconLarge, weight: .semibold))
                                    .foregroundColor(Theme.Color.text)
                                    .frame(width: 56, height: 56)
                                    .rotationEffect(viewModel.iconOrientation)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, Theme.Layout.viewfinderInset)
                    }
                    .padding(.bottom, Theme.Layout.paddingLarge)
                }
                .frame(width: geometry.size.width)
                
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
                                .background(Capsule().fill(Theme.Color.text))
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
            .preferredColorScheme(appTheme.colorScheme)
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
