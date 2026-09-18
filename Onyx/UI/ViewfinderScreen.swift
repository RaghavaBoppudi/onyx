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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopControlBar(
                    isGridVisible: settings.isGridVisible,
                    isSettingsOpen: isAppearancePanelVisible,
                    glyphRotation: glyphRotation,
                    onToggleGrid: {
                        Haptics.shared.fire(.toggle)
                        withAnimation(.reduceMotionAware(Metrics.Motion.gridFade)) { settings.isGridVisible.toggle() }
                    },
                    onOpenSettings: {
                        Haptics.shared.fire(.toggle)
                        withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) {
                            isAppearancePanelVisible.toggle()
                        }
                    }
                )
                .visible(!isBrowsingLooks)
                .disabled(model.isAwaitingSecondFrame)
                .opacity(model.isAwaitingSecondFrame ? 0.35 : 1)

                viewfinder
                    .padding(.horizontal, Metrics.Viewfinder.inset)
                    .opacity(isBrowsingLooks ? 0 : 1)

                Spacer()

                BottomControlBar(
                    thumbnail: model.recentPhoto.thumbnail,
                    thumbnailAssetIdentifier: model.recentPhoto.assetIdentifier,
                    flashMode: settings.flashMode,
                    isBusy: model.isBusy,
                    isCaptureRestricted: model.isAwaitingSecondFrame,
                    glyphRotation: glyphRotation,
                    onOpenPhotos: { model.openPhotosApp() },
                    onCycleFlash: {
                        Haptics.shared.fire(.toggle)
                        settings.cycleFlash()
                    },
                    onCapture: { Task { await model.capture() } }
                )
                .visible(!isBrowsingLooks)

                Spacer()

                looksEntryButton
                    .frame(maxWidth: .infinity)

                Spacer()
            }

            if isBrowsingLooks {
                GeometryReader { proxy in
                    let carouselWidth = proxy.size.width
                    let carouselHeight = carouselWidth / Metrics.Viewfinder.aspect

                    LookCardCarousel(
                        looks: LookKind.allCases,
                        selectedID: pendingLook.id,
                        boxSize: CGSize(width: carouselWidth, height: carouselHeight),
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
                    .frame(width: carouselWidth, height: carouselHeight)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2 + Metrics.LookCarousel.centerOffsetY
                    )
                }
            }
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

    private var looksEntryButton: some View {
        Button(action: {
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
        }) {
            Group {
                if isBrowsingLooks {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Metrics.Chrome.iconPointSize, weight: .bold))
                        .frame(width: Metrics.Chrome.tapTarget, height: Metrics.Chrome.tapTarget)
                } else if model.isAwaitingSecondFrame {
                    Text("Cancel")
                        .font(Typography.panelHeader)
                        .padding(.horizontal, 24)
                        .frame(height: Metrics.Chrome.tapTarget)
                } else {
                    Text("Looks")
                        .font(Typography.panelHeader)
                        .padding(.horizontal, 24)
                        .frame(height: Metrics.Chrome.tapTarget)
                }
            }
            .foregroundStyle(
                !isBrowsingLooks && (model.isAwaitingSecondFrame || isNonDefaultLookActive)
                    ? theme.accent
                    : theme.iconActive
            )
        }
        .buttonStyle(.plain)
        .onyxGlass(in: .capsule)
        .accessibilityLabel(
            isBrowsingLooks ? "Back" : (model.isAwaitingSecondFrame ? "Cancel double exposure" : "Looks")
        )
        .accessibilityValue(
            !isBrowsingLooks && !model.isAwaitingSecondFrame && isNonDefaultLookActive
                ? model.selectedLook.displayName
                : ""
        )
        .animation(.reduceMotionAware(Metrics.Motion.panelReveal), value: isBrowsingLooks)
        .animation(.reduceMotionAware(Metrics.Motion.panelReveal), value: model.isAwaitingSecondFrame)
    }

    private var viewfinder: some View {
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
        .aspectRatio(Metrics.Viewfinder.aspect, contentMode: .fit)
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
