import SwiftUI

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var settings: AppSettings
    let model: CameraModel

    @State private var isAppearancePanelVisible = false
    @State private var lifecycleTask: Task<Void, Never>?
    @State private var isBrowsingLooks = false
    @State private var pendingLook: LookKind = .standard

    private var glyphRotation: Angle {
        .degrees(model.rotation.glyphRotationDegrees)
    }

    private var displayedLook: LookKind {
        isBrowsingLooks ? pendingLook : model.selectedLook
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
            .visible(!isBrowsingLooks)

            viewfinder
                .padding(.horizontal, Metrics.Viewfinder.inset)

            Spacer()

            Text(pendingLook.summary)
                .font(Typography.caption)
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .visible(isBrowsingLooks, interactive: false)

            ZStack {
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
                .visible(!isBrowsingLooks)

                LooksSelector(
                    looks: LookKind.allCases,
                    selectedID: pendingLook.id,
                    onSelect: { look in
                        Haptics.shared.fire(.selection)
                        pendingLook = look
                    }
                )
                .visible(isBrowsingLooks)
            }

            Spacer()

            LooksToggle(
                currentLookName: model.selectedLook.displayName,
                isBrowsing: Binding(
                    get: { isBrowsingLooks },
                    set: { newValue in
                        if newValue {
                            pendingLook = model.selectedLook
                            isBrowsingLooks = true
                        } else {
                            confirmLook()
                        }
                    }
                )
            )
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button(action: confirmLook) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Metrics.Chrome.iconPointSize, weight: .bold))
                        .foregroundStyle(theme.iconActive)
                        .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .visible(isBrowsingLooks)
                .offset(x: 48)
            }

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

    private func confirmLook() {
        model.setLook(pendingLook)
        isBrowsingLooks = false
    }

    private var viewfinder: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(
                sessionBox: model.sessionBox,
                rotation: model.rotation
            )
            .aspectRatio(Metrics.Viewfinder.aspect, contentMode: .fit)
            .saturation(displayedLook == .mono ? 0 : 1)
            .background(theme.viewfinderVoid)
            .overlay {
                if !model.whiteBalance.hasConverged {
                    theme.viewfinderVoid
                        .transition(.opacity)
                }
            }
            .animation(Metrics.Motion.gridFade, value: model.whiteBalance.hasConverged)
            .overlay { if settings.isGridVisible, !isBrowsingLooks { RuleOfThirdsGrid() } }
            .overlay {
                theme.shutterBlink
                    .opacity(model.blinkOpacity)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                if !isBrowsingLooks {
                    LensSelector(
                        lenses: model.lenses,
                        selectedID: model.selectedLens?.id,
                        onSelect: { lens in Task { await model.select(lens) } }
                    )
                    .padding(.bottom, Metrics.LensSelector.bottomInset)
                }
            }
            .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))
            .opacity(model.isSwitching ? 0.55 : 1)
            .animation(Metrics.Motion.lensSwitch, value: model.isSwitching)

            if isAppearancePanelVisible, !isBrowsingLooks {
                AppearancePanel(selection: $settings.appearance)
                    .padding(8)
            }

            if model.isOnDimmerLens, !isAppearancePanelVisible, !isBrowsingLooks {
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

fileprivate extension View {
    func visible(_ isVisible: Bool, interactive: Bool = true) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible && interactive)
    }
}
