import SwiftUI
import UIKit

struct ViewfinderScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let settings: AppSettings
    let model: CameraModel

    @State private var showsModes = false
    @State private var showsLowLight = false

    private enum Layout {
        static let verticalControlsAspectThreshold: CGFloat = 1.8
        static let railVerticalInset: CGFloat = 40
        static let railHorizontalGap: CGFloat = 16
        static let railWidth: CGFloat = 104
        static let statusRailWidth: CGFloat = 64
    }

    var body: some View {
        GeometryReader { proxy in
            layout(in: proxy.size, insets: proxy.safeAreaInsets)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) { modeDrawer }
                .animation(.smooth(duration: 0.35), value: showsModes)
                .onChange(of: DualLayoutStyle.resolve(for: proxy.size), initial: true) { _, style in
                    model.updateDualLayout(style)
                }
        }
        .environment(\.glyphRotation, model.reference.glyphRotation)
        .background {
            HardwareShutter {
                if model.acceptsShutter { Task { await model.capture() } }
            }
            .allowsHitTesting(false)
        }
        .sensoryFeedback(trigger: model.feedback) { _, event in
            event.serial == 0 ? nil : event.kind.sensoryFeedback
        }
        .alert(
            "Permission Needed",
            isPresented: settingsAlertBinding,
            presenting: model.notice
        ) { _ in
            Button("Open Settings") { openSettings() }
            Button("Not Now", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
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
    private var modeDrawer: some View {
        if showsModes {
            ModeDrawer(model: model) { showsModes = false }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var settingsAlertBinding: Binding<Bool> {
        Binding(
            get: { model.notice?.showsSettings == true },
            set: { if !$0 { model.dismissNotice() } }
        )
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    @ViewBuilder
    private func layout(in size: CGSize, insets: EdgeInsets) -> some View {
        let isLandscape = size.width > size.height
        let prefersRail = size.height / max(size.width, 1) < Layout.verticalControlsAspectThreshold

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
            viewfinder(isLandscape: isLandscape, cornerRadius: Metrics.Viewfinder.cornerRadius)
                .padding(.leading, Metrics.Viewfinder.inset)
                .padding(.vertical, Layout.railVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VerticalControlRail(
                settings: settings,
                model: model,
                onShowModes: { showsModes = true }
            )
            .frame(width: Layout.railWidth)
            .padding(.horizontal, Layout.railHorizontalGap)
            .hiddenWhileBrowsing(showsModes)
        }
    }

    private var statusRailLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                viewfinder(isLandscape: false, cornerRadius: Metrics.Viewfinder.cornerRadius)
                    .padding(.leading, Metrics.Viewfinder.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusControls(
                    settings: settings,
                    axis: .vertical,
                    model: model,
                    onShowModes: { showsModes = true }
                )
                .frame(width: Layout.statusRailWidth)
                .padding(.horizontal, Layout.railHorizontalGap)
                .hiddenWhileBrowsing(showsModes)
            }
            .padding(.top, Layout.railVerticalInset)
            .frame(maxHeight: .infinity)

            Spacer(minLength: Layout.railVerticalInset)

            BottomControlBar(model: model)
                .padding(.bottom, Layout.railVerticalInset)
                .hiddenWhileBrowsing(showsModes)
        }
    }

    private func standardLayout(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            StatusControls(
                settings: settings,
                axis: .horizontal,
                model: model,
                onShowModes: { showsModes = true }
            )
                .hiddenWhileBrowsing(showsModes)

            viewfinder(isLandscape: false, cornerRadius: 0)

            Spacer(minLength: 12)

            BottomControlBar(model: model)
                .hiddenWhileBrowsing(showsModes)

            Spacer(minLength: 8)
        }
        .padding(insets)
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

    private var coverOpacity: Double {
        if !model.whiteBalance.hasConverged { return 1 }
        return model.isSwitching ? 0.45 : 0
    }

    private var previewIsMono: Bool {
        model.selectedMode.isMono && !model.isDualActive
    }

    private func viewfinder(isLandscape: Bool, cornerRadius: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                preview
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .saturation(previewIsMono ? 0 : 1)
                    .background(Color.black)
                    .overlay {
                        Color.black
                            .opacity(coverOpacity)
                            .allowsHitTesting(false)
                    }
                    .animation(.easeInOut(duration: 0.2), value: coverOpacity)
                    .overlay {
                        if settings.isGridVisible { RuleOfThirdsGrid() }
                    }
                    .animation(.easeInOut(duration: 0.18), value: settings.isGridVisible)
                    .overlay {
                        Color.black
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
                    .animation(.easeInOut(duration: 0.18), value: model.isAwaitingSecondFrame)
                    .overlay(alignment: .bottom) {
                        if model.pipeline == .single, model.visibleLenses.count > 1 {
                            LensPicker(model: model)
                                .padding(.bottom, 12)
                        }
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))

                VStack(spacing: 8) {
                    if showsLowLight, model.pipeline == .single {
                        NoticeBanner(message: "This lens gathers less light", onTap: nil)
                    }
                    if let notice = model.notice, !notice.showsSettings {
                        NoticeBanner(message: notice.message, onTap: { model.dismissNotice() })
                    }
                }
                .padding(.top, 14)
            }
            .animation(.easeInOut(duration: 0.18), value: showsLowLight)
            .animation(.easeInOut(duration: 0.18), value: model.notice)
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
            .onChange(of: model.notice) { _, notice in
                if let notice { AccessibilityNotification.Announcement(notice.message).post() }
            }
        }
        .aspectRatio(Metrics.Viewfinder.aspect(isLandscape: isLandscape), contentMode: .fit)
        .animation(.snappy(duration: 0.26), value: isLandscape)
    }
}

private extension View {
    func hiddenWhileBrowsing(_ isBrowsing: Bool) -> some View {
        opacity(isBrowsing ? 0 : 1)
            .allowsHitTesting(!isBrowsing)
            .animation(.smooth(duration: 0.2), value: isBrowsing)
    }
}

private struct NoticeBanner: View {
    let message: String
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(message)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.72), in: .capsule)
        .padding(.horizontal, 24)
        .transition(.opacity)
        .disabled(onTap == nil)
    }
}

private struct RuleOfThirdsGrid: View {
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
            .stroke(.white.opacity(0.34), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private struct BottomControlBar: View {
    let model: CameraModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            CaptureThumbnail(model: model)
            Spacer()
            ShutterButton(model: model)
            Spacer()
            CameraFlipButton(model: model)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}
