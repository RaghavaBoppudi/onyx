import SwiftUI

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var settings: AppSettings
    let model: CameraModel

    @State private var isAppearancePanelVisible = false
    @State private var lifecycleTask: Task<Void, Never>?

    private var glyphRotation: Angle {
        .degrees(model.rotation.glyphRotationDegrees)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopControlBar(
                isGridVisible: settings.isGridVisible,
                isSettingsOpen: isAppearancePanelVisible,
                glyphRotation: glyphRotation,
                onToggleGrid: {
                    Haptics.shared.fire(.toggle)
                    withAnimation(Metrics.Motion.gridFade) { settings.isGridVisible.toggle() }
                },
                onOpenSettings: {
                    Haptics.shared.fire(.toggle)
                    withAnimation(Metrics.Motion.panelReveal) {
                        isAppearancePanelVisible.toggle()
                    }
                }
            )

            viewfinder
                .padding(.horizontal, Metrics.Viewfinder.inset)

            Spacer()

            BottomControlBar(
                thumbnail: model.recentPhoto.thumbnail,
                thumbnailAssetIdentifier: model.recentPhoto.assetIdentifier,
                flashMode: settings.flashMode,
                isBusy: model.isBusy,
                glyphRotation: glyphRotation,
                onOpenPhotos: { model.openPhotosApp() },
                onCycleFlash: {
                    Haptics.shared.fire(.toggle)
                    settings.cycleFlash()
                },
                onCapture: { Task { await model.capture() } }
            )

            Spacer()
        }
        .background(theme.canvas.ignoresSafeArea())
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            let previous = lifecycleTask
            lifecycleTask = Task {
                _ = await previous?.value
                if phase == .active {
                    await model.start()
                } else {
                    await model.stop()
                }
            }
        }
    }

    private var viewfinder: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(
                sessionBox: model.sessionBox,
                rotation: model.rotation
            )
            .aspectRatio(Metrics.Viewfinder.aspect, contentMode: .fit)
            .background(theme.viewfinderVoid)
            .overlay { if settings.isGridVisible { RuleOfThirdsGrid() } }
            .overlay {
                theme.shutterBlink
                    .opacity(model.blinkOpacity)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LensSelector(
                    lenses: model.lenses,
                    selectedID: model.selectedLens?.id,
                    onSelect: { lens in Task { await model.select(lens) } }
                )
                .padding(.bottom, Metrics.LensSelector.bottomInset)
            }
            .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))
            .opacity(model.isSwitching ? 0.55 : 1)
            .animation(Metrics.Motion.lensSwitch, value: model.isSwitching)

            if isAppearancePanelVisible {
                AppearancePanel(selection: $settings.appearance)
                    .padding(8)
            }

            if model.isOnDimmerLens, !isAppearancePanelVisible {
                LowLightBanner()
                    .padding(.top, 14)
            }
        }
        .animation(Metrics.Motion.gridFade, value: model.isOnDimmerLens)
    }
}

private struct LowLightBanner: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Caution: Smaller apertures result in darker images")
            .font(Typography.caption)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .onyxGlass(in: .capsule)
            .transition(.opacity)
    }
}

private struct RuleOfThirdsGrid: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                for step in 1...2 {
                    let x = width * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))

                    let y = height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(theme.gridLine, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
