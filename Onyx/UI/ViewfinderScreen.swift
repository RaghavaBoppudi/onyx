import SwiftUI
import UIKit

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var settings: AppSettings
    let model: CameraModel

    @State private var isAppearancePanelVisible = false
    @State private var isBrowsingLooks = false
    @State private var lifecycleTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                layout(in: proxy.size)
                    .opacity(isBrowsingLooks ? 0 : 1)
                    .allowsHitTesting(!isBrowsingLooks)

                if isBrowsingLooks {
                    LookCardCarousel(
                        looks: LookKind.allCases,
                        selected: model.selectedLook,
                        onConfirm: { look in confirmLook(look) }
                    )
                    .transition(.opacity)
                }
            }
            .background(theme.canvas.ignoresSafeArea())
        }
        .environment(\.glyphRotation, model.rotation.glyphRotation)
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

    @ViewBuilder
    private func layout(in size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let prefersRail = size.height / max(size.width, 1) < Metrics.Chrome.verticalControlsAspectThreshold

        if UIDevice.current.userInterfaceIdiom == .pad || (prefersRail && isLandscape) {
            railLayout(isLandscape: isLandscape)
        } else if prefersRail {
            statusRailLayout
        } else {
            standardLayout
        }
    }

    private func railLayout(isLandscape: Bool) -> some View {
        HStack(spacing: 0) {
            viewfinder(isLandscape: isLandscape)
                .padding(.leading, Metrics.Viewfinder.inset)
                .padding(.vertical, Metrics.Chrome.railVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VerticalControlRail(
                model: model,
                settings: settings,
                isSettingsOpen: isAppearancePanelVisible,
                onOpenSettings: { toggleAppearancePanel() },
                onLooksAction: { handleLooksAction() }
            )
            .frame(width: Metrics.Chrome.railWidth)
            .padding(.horizontal, Metrics.Chrome.railHorizontalGap)
        }
        .ignoresSafeArea()
    }

    private var statusRailLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                viewfinder(isLandscape: false)
                    .padding(.leading, Metrics.Viewfinder.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                statusControls(axis: .vertical)
                    .frame(width: Metrics.Chrome.statusRailWidth)
                    .padding(.horizontal, Metrics.Chrome.railHorizontalGap)
            }
            .padding(.top, Metrics.Chrome.railVerticalInset)
            .frame(maxHeight: .infinity)

            Spacer(minLength: Metrics.Chrome.railVerticalInset)

            BottomControlBar(model: model, onLooksAction: { handleLooksAction() })
                .padding(.bottom, Metrics.Chrome.railVerticalInset)
        }
        .ignoresSafeArea()
    }

    private var standardLayout: some View {
        VStack(spacing: 0) {
            statusControls(axis: .horizontal)

            viewfinder(isLandscape: false)
                .padding(.horizontal, Metrics.Viewfinder.inset)

            Spacer()

            BottomControlBar(model: model, onLooksAction: { handleLooksAction() })

            Spacer()
        }
    }

    private func statusControls(axis: Axis) -> some View {
        StatusControls(
            axis: axis,
            settings: settings,
            isSettingsOpen: isAppearancePanelVisible,
            isRestricted: model.isAwaitingSecondFrame,
            onOpenSettings: { toggleAppearancePanel() }
        )
    }

    private func toggleAppearancePanel() {
        Haptics.shared.fire(.toggle)
        withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) {
            isAppearancePanelVisible.toggle()
        }
    }

    private func handleLooksAction() {
        if model.isAwaitingSecondFrame {
            model.cancelDoubleExposureSequence()
        } else {
            Haptics.shared.fire(.toggle)
            withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) { isBrowsingLooks = true }
        }
    }

    private func confirmLook(_ look: LookKind) {
        Haptics.shared.fire(.selection)
        model.setLook(look)
        withAnimation(.reduceMotionAware(Metrics.Motion.panelReveal)) { isBrowsingLooks = false }
    }

    private func viewfinder(isLandscape: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                CameraPreviewView(
                    sessionBox: model.sessionBox,
                    rotation: model.rotation
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .saturation(model.selectedLook.isMono ? 0 : 1)
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
                    if let ghost = model.ghostOverlay {
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
