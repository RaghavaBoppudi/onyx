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

    private var isNonDefaultLookActive: Bool {
        model.selectedLook != .standard
    }

    private var looksState: LooksControlState {
        if isBrowsingLooks { return .browsing }
        if model.isAwaitingSecondFrame { return .awaitingSecondFrame }
        return .closed(isNonDefaultActive: isNonDefaultLookActive)
    }

    var body: some View {
        GeometryReader { screenProxy in
            let heightToWidth = screenProxy.size.height / max(screenProxy.size.width, 1)
            let isLandscape = screenProxy.size.width > screenProxy.size.height
            let useVerticalControls = heightToWidth < Metrics.Chrome.verticalControlsAspectThreshold

            let toggleGrid = {
                Haptics.shared.fire(.toggle)
                withAnimation(.reduceMotionAware(Metrics.Motion.gridFade)) { settings.isGridVisible.toggle() }
            }
            let cycleFlash = {
                Haptics.shared.fire(.toggle)
                settings.cycleFlash()
            }
            let openSettings = {
                Haptics.shared.fire(.toggle)
                withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) {
                    isAppearancePanelVisible.toggle()
                }
            }
            let openPhotos = { model.openPhotosApp() }
            let capture: () -> Void = { Task { await model.capture() } }

            ZStack {
                if isBrowsingLooks {
                    LookCardCarousel(
                        looks: LookKind.allCases,
                        selectedID: pendingLook.id,
                        onPreview: { look in
                            Haptics.shared.fire(.selection)
                            pendingLook = look
                        },
                        onConfirm: { look in
                            Haptics.shared.fire(.selection)
                            model.setLook(look)
                            pendingLook = look
                            isBrowsingLooks = false
                        }
                    )
                }

                if useVerticalControls {
                    if isLandscape {
                        HStack(spacing: 0) {
                            viewfinder(isLandscape: true)
                                .padding(.leading, Metrics.Viewfinder.inset)
                                .padding(.vertical, Metrics.Chrome.railVerticalInset)
                                .opacity(isBrowsingLooks ? 0 : 1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            VerticalControlRail(
                                isGridVisible: settings.isGridVisible,
                                isSettingsOpen: isAppearancePanelVisible,
                                flashMode: settings.flashMode,
                                thumbnail: model.recentPhoto.thumbnail,
                                thumbnailAssetIdentifier: model.recentPhoto.assetIdentifier,
                                isBusy: model.isBusy,
                                isCaptureRestricted: model.isAwaitingSecondFrame,
                                isBrowsingLooks: isBrowsingLooks,
                                looksState: looksState,
                                glyphRotation: glyphRotation,
                                onToggleGrid: toggleGrid,
                                onCycleFlash: cycleFlash,
                                onOpenSettings: openSettings,
                                onOpenPhotos: openPhotos,
                                onCapture: capture,
                                onLooksAction: handleLooksAction
                            )
                            .frame(width: Metrics.Chrome.railWidth)
                            .padding(.horizontal, Metrics.Chrome.railHorizontalGap)
                        }
                        .ignoresSafeArea()
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                viewfinder(isLandscape: false)
                                    .padding(.leading, Metrics.Viewfinder.inset)
                                    .opacity(isBrowsingLooks ? 0 : 1)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                StatusIconRail(
                                    isGridVisible: settings.isGridVisible,
                                    isSettingsOpen: isAppearancePanelVisible,
                                    flashMode: settings.flashMode,
                                    isBrowsingLooks: isBrowsingLooks,
                                    isCaptureRestricted: model.isAwaitingSecondFrame,
                                    glyphRotation: glyphRotation,
                                    onToggleGrid: toggleGrid,
                                    onCycleFlash: cycleFlash,
                                    onOpenSettings: openSettings
                                )
                                .frame(width: Metrics.Chrome.statusRailWidth)
                                .padding(.horizontal, Metrics.Chrome.railHorizontalGap)
                            }
                            .padding(.top, Metrics.Chrome.railVerticalInset)
                            .frame(maxHeight: .infinity)

                            Spacer(minLength: Metrics.Chrome.railVerticalInset)

                            BottomControlBar(
                                thumbnail: model.recentPhoto.thumbnail,
                                thumbnailAssetIdentifier: model.recentPhoto.assetIdentifier,
                                isBusy: model.isBusy,
                                isCaptureRestricted: model.isAwaitingSecondFrame,
                                isBrowsingLooks: isBrowsingLooks,
                                looksState: looksState,
                                glyphRotation: glyphRotation,
                                onOpenPhotos: openPhotos,
                                onCapture: capture,
                                onLooksAction: handleLooksAction
                            )
                            .padding(.bottom, Metrics.Chrome.railVerticalInset)
                        }
                        .ignoresSafeArea()
                    }
                } else {
                    VStack(spacing: 0) {
                        TopControlBar(
                            isGridVisible: settings.isGridVisible,
                            isSettingsOpen: isAppearancePanelVisible,
                            flashMode: settings.flashMode,
                            glyphRotation: glyphRotation,
                            onToggleGrid: toggleGrid,
                            onCycleFlash: cycleFlash,
                            onOpenSettings: openSettings
                        )
                        .opacity(isBrowsingLooks ? 0 : 1)
                        .disabled(isBrowsingLooks || model.isAwaitingSecondFrame)
                        .opacity(model.isAwaitingSecondFrame ? 0.35 : 1)

                        viewfinder(isLandscape: isLandscape)
                            .padding(.horizontal, Metrics.Viewfinder.inset)
                            .opacity(isBrowsingLooks ? 0 : 1)

                        Spacer()

                        BottomControlBar(
                            thumbnail: model.recentPhoto.thumbnail,
                            thumbnailAssetIdentifier: model.recentPhoto.assetIdentifier,
                            isBusy: model.isBusy,
                            isCaptureRestricted: model.isAwaitingSecondFrame,
                            isBrowsingLooks: isBrowsingLooks,
                            looksState: looksState,
                            glyphRotation: glyphRotation,
                            onOpenPhotos: openPhotos,
                            onCapture: capture,
                            onLooksAction: handleLooksAction
                        )

                        Spacer()
                    }
                }
            }
            .background(theme.canvas.ignoresSafeArea())
        }
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

    private func handleLooksAction() {
        if isBrowsingLooks {
            model.setLook(pendingLook)
            withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) { isBrowsingLooks = false }
        } else if model.isAwaitingSecondFrame {
            model.cancelDoubleExposureSequence()
        } else {
            Haptics.shared.fire(.toggle)
            pendingLook = model.selectedLook
            withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) { isBrowsingLooks = true }
            Haptics.shared.prepare()
        }
    }

    private func viewfinder(isLandscape: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                CameraPreviewView(
                    sessionBox: model.sessionBox,
                    rotation: model.rotation
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .saturation(model.selectedLook == .mono || model.selectedLook == .doubleExposureMono ? 0 : 1)
                .background(theme.viewfinderVoid)
                .overlay {
                    if !model.whiteBalance.hasConverged {
                        theme.viewfinderVoid
                            .transition(.opacity)
                    }
                }
                .animation(.reduceMotionAware(Metrics.Motion.gridFade), value: model.whiteBalance.hasConverged)
                .overlay { if settings.isGridVisible { RuleOfThirdsGrid() } }
                .overlay {
                    theme.shutterBlink
                        .opacity(model.blinkOpacity)
                        .allowsHitTesting(false)
                }
                .overlay {
                    if case .awaitingSecondFrame(let ghost) = model.exposureStage {
                        Image(uiImage: ghost)
                            .resizable()
                            .scaledToFill()
                            .opacity(DoubleExposureProfile.ghostOverlayOpacity)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.reduceMotionAware(Metrics.Motion.gridFade), value: model.isAwaitingSecondFrame)
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
                .animation(.reduceMotionAware(Metrics.Motion.lensSwitch), value: model.isSwitching)

                if isAppearancePanelVisible {
                    AppearancePanel(selection: $settings.appearance)
                        .padding(8)
                }

                if model.isOnDimmerLens, !isAppearancePanelVisible {
                    LowLightBanner()
                        .padding(.top, 14)
                }
            }
            .animation(.reduceMotionAware(Metrics.Motion.gridFade), value: model.isOnDimmerLens)
        }
        .aspectRatio(Metrics.Viewfinder.aspect(isLandscape: isLandscape), contentMode: .fit)
        .animation(.reduceMotionAware(Metrics.Motion.lensSwitch), value: isLandscape)
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
