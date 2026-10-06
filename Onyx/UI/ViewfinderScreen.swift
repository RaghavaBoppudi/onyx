import SwiftUI
import UIKit

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let settings: AppSettings
    let model: CameraModel

    @State private var isBrowsingModes = false
    @State private var showsLowLight = false
    @State private var modesFrame: CGRect?
    @State private var browsedModeID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                layout(in: proxy.size, insets: proxy.safeAreaInsets)
                    .environment(\.isBrowsingModes, isOverlayActive)
                    .scaleEffect(isOverlayActive && !reduceMotion ? 0.94 : 1)
                    .opacity(isOverlayActive ? 0 : 1)
                    .allowsHitTesting(!isOverlayActive)
                    .accessibilityHidden(isOverlayActive)

                if isBrowsingModes {
                    ModeCardCarousel(
                        modes: model.availableModes,
                        activeID: $browsedModeID,
                        position: model.cameraPosition,
                        topInset: proxy.safeAreaInsets.top,
                        avoiding: modesFrame,
                        onConfirm: { mode in confirmMode(mode) },
                        onDismiss: { closeModes() }
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.05).combined(with: .opacity))
                }

                if model.isViewingLatest {
                    LatestPhotoViewer(
                        model: model,
                        topInset: proxy.safeAreaInsets.top,
                        avoiding: modesFrame
                    )
                    .transition(.opacity)
                }
            }
            .coordinateSpace(.named(ViewfinderSpace.name))
            .onPreferenceChange(ModesIconFrameKey.self) { frame in
                if let frame { modesFrame = frame }
            }
            .overlay {
                modesBackButton(modesFrame)
            }
            .background(theme.canvas)
            .ignoresSafeArea()
            .onChange(of: DualLayoutStyle.resolve(for: proxy.size), initial: true) { _, style in
                model.updateDualLayout(style)
            }
        }
        .environment(\.glyphRotation, model.reference.glyphRotation)
        .onChange(of: model.location.isAccessDenied) { _, isDenied in
            if isDenied { model.geotagAccessDenied() }
        }
        .task(id: scenePhase) {
            switch scenePhase {
            case .active: await model.start()
            case .background: await model.stop()
            default: break
            }
        }
    }

    @ViewBuilder
    private func layout(in size: CGSize, insets: EdgeInsets) -> some View {
        let isLandscape = size.width > size.height
        let prefersRail = size.height / max(size.width, 1) < Metrics.Chrome.verticalControlsAspectThreshold

        if UIDevice.current.userInterfaceIdiom == .pad || (prefersRail && isLandscape) {
            railLayout(isLandscape: isLandscape)
        } else if prefersRail {
            statusRailLayout
        } else {
            standardLayout(insets: insets)
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
                onModesAction: { handleModesAction() }
            )
            .frame(width: Metrics.Chrome.railWidth)
            .padding(.horizontal, Metrics.Chrome.railHorizontalGap)
        }
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

            BottomControlBar(model: model)

            modeButton
                .padding(.top, 8)
                .padding(.bottom, Metrics.Chrome.railVerticalInset)
        }
    }

    private func standardLayout(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            statusControls(axis: .horizontal)

            viewfinder(isLandscape: false)
                .padding(.horizontal, Metrics.Viewfinder.inset)

            Spacer()

            BottomControlBar(model: model)

            modeButton
                .padding(.top, 16)

            Spacer()
        }
        .padding(insets)
    }

    private func statusControls(axis: Axis) -> some View {
        StatusControls(
            axis: axis,
            settings: settings,
            model: model
        )
    }

    private var modeButton: some View {
        ModeButton(model: model, action: { handleModesAction() })
    }

    private func handleModesAction() {
        if model.isAwaitingSecondFrame {
            model.cancelDoubleExposureSequence()
        } else {
            Haptics.shared.fire(.toggle)
            browsedModeID = model.selectedMode.id
            setBrowsing(true)
        }
    }

    private func closeModes() {
        let browsed = model.availableModes.first { $0.id == browsedModeID }
        if let browsed, browsed != model.selectedMode {
            confirmMode(browsed)
        } else {
            setBrowsing(false)
        }
    }

    private var isOverlayActive: Bool {
        isBrowsingModes || model.isViewingLatest
    }

    private func closeLatestPhoto() {
        withAnimation(revealAnimation) { model.hideLatestPhoto() }
    }

    @ViewBuilder
    private func modesBackButton(_ frame: CGRect?) -> some View {
        if isOverlayActive {
            let button = PillButton(title: "Back", systemImage: Symbols.back.outline) {
                Haptics.shared.fire(.toggle)
                if model.isViewingLatest {
                    closeLatestPhoto()
                } else {
                    closeModes()
                }
            }
            .accessibilityLabel("Back to camera")
            .transition(.opacity)

            if let frame {
                button.position(x: frame.midX, y: frame.midY)
            } else {
                button
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, Metrics.Chrome.edgeInset)
            }
        }
    }

    private var revealAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Metrics.Motion.panelReveal
    }

    private func setBrowsing(_ isBrowsing: Bool) {
        withAnimation(revealAnimation) { isBrowsingModes = isBrowsing }
    }

    private func confirmMode(_ mode: CaptureMode) {
        Haptics.shared.fire(.selection)
        Task { await model.setMode(mode) }
        setBrowsing(false)
    }

    @ViewBuilder
    private var preview: some View {
        switch model.pipeline {
        case .single:
            CameraPreviewView(
                sessionBox: model.sessionBox,
                rotation: model.rotation
            )
        case .dual:
            DualPreviewView(
                box: model.dualBox,
                rotation: model.rotation,
                secondaryRotation: model.secondaryRotation,
                style: model.dualLayout
            )
        }
    }

    private func viewfinder(isLandscape: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                preview
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .saturation(model.selectedMode.isMono && !model.isDualActive ? 0 : 1)
                    .opacity(model.isSwitching ? 0.55 : 1)
                    .onyxAnimation(Metrics.Motion.previewDim, value: model.isSwitching)
                    .background(theme.viewfinderVoid)
                    .overlay {
                        if !model.whiteBalance.hasConverged {
                            theme.viewfinderVoid
                                .transition(.opacity)
                        }
                    }
                    .onyxAnimation(Metrics.Motion.gridFade, value: model.whiteBalance.hasConverged)
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
                    .onyxAnimation(Metrics.Motion.gridFade, value: model.isAwaitingSecondFrame)
                    .overlay(alignment: .bottom) {
                        if model.pipeline == .single {
                            LensSelector(
                                lenses: model.visibleLenses,
                                selectedID: model.selectedLens?.id,
                                pendingID: model.pendingLensID,
                                onSelect: { lens in model.requestLens(lens) }
                            )
                            .padding(.bottom, Metrics.LensSelector.bottomInset)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))

                VStack(spacing: 8) {
                    if showsLowLight, model.pipeline == .single {
                        LowLightBanner()
                    }
                    if let notice = model.notice {
                        NoticeBanner(notice: notice, onDismiss: { model.dismissNotice() })
                    }
                }
                .padding(.top, 14)
            }
            .onyxAnimation(Metrics.Motion.gridFade, value: showsLowLight)
            .task(id: model.selectedLens?.id) {
                guard model.isOnDimmerLens else {
                    showsLowLight = false
                    return
                }
                showsLowLight = true
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                showsLowLight = false
            }
            .onyxAnimation(Metrics.Motion.gridFade, value: model.notice)
            .onChange(of: model.notice) { _, notice in
                if let notice { AccessibilityNotification.Announcement(notice.message).post() }
            }
        }
        .aspectRatio(Metrics.Viewfinder.aspect(isLandscape: isLandscape), contentMode: .fit)
        .onyxAnimation(Metrics.Motion.lensSwitch, value: isLandscape)
    }
}

private struct NoticeBanner: View {
    @Environment(\.theme) private var theme

    let notice: Notice
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(notice.message)
                .font(Typography.caption)
                .foregroundStyle(theme.iconActive)
                .multilineTextAlignment(.center)

            if notice.showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.iconActive)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.canvas.opacity(0.92), in: .rect(cornerRadius: Metrics.Panel.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Panel.cornerRadius)
                .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
        }
        .padding(.horizontal, 24)
        .onTapGesture(perform: onDismiss)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

private struct LowLightBanner: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("This lens gathers less light")
            .font(Typography.caption)
            .foregroundStyle(theme.iconActive)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .onyxPill()
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

private struct LatestPhotoViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let model: CameraModel
    let topInset: CGFloat
    let avoiding: CGRect?

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            let region = imageRegion(in: proxy.size)

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: Metrics.Viewfinder.cornerRadius)
                                .strokeBorder(theme.thumbnailBorder, lineWidth: Metrics.Thumbnail.borderWidth)
                        }
                        .accessibilityLabel("Most recent photo")
                } else if didFail {
                    Text("That photo couldn't be loaded.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.secondary)
                } else {
                    ProgressView()
                        .tint(theme.iconActive)
                }
            }
            .frame(width: region.width, height: region.height)
            .position(x: region.midX, y: region.midY)
            .overlay(alignment: .topTrailing) {
                PillButton(title: "Photos", systemImage: "arrow.up.right.square") {
                    model.openPhotosApp()
                }
                .accessibilityLabel("Open in Photos")
                .padding(.top, topInset + Metrics.Chrome.edgeInset)
                .padding(.trailing, Metrics.Chrome.edgeInset + 8)
            }
            .task {
                let target = CGSize(
                    width: region.width * displayScale,
                    height: region.height * displayScale
                )
                image = await model.recentPhoto.fullImage(targetSize: target)
                didFail = image == nil
            }
        }
    }

    private func imageRegion(in size: CGSize) -> CGRect {
        let top = max(topInset + 64, size.height * 0.1)
        var bottom = size.height - Metrics.ModeCarousel.edgeMargin

        if let avoiding {
            let columnMinX = size.width * 0.25
            let columnMaxX = size.width * 0.75
            if avoiding.maxX > columnMinX, avoiding.minX < columnMaxX {
                bottom = min(bottom, avoiding.minY - Metrics.ModeCarousel.avoidanceGap)
            }
        }

        let margin: CGFloat = 16
        return CGRect(
            x: margin,
            y: top,
            width: size.width - margin * 2,
            height: max(bottom - top, Metrics.ModeCarousel.minimumCardHeight)
        )
    }
}
