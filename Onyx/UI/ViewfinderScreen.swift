//  ViewfinderScreen.swift
//  Composition root for the capture UI. Holds no camera logic.

import SwiftUI

struct ViewfinderScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var settings: AppSettings
    let model: CameraModel

    @State private var isAppearancePanelVisible = false

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

            Spacer(minLength: 12)

            LensSelector(
                lenses: model.lenses,
                selectedID: model.selectedLens?.id,
                onSelect: { lens in Task { await model.select(lens) } }
            )

            Spacer(minLength: 20)

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
            .padding(.bottom, 24)
        }
        .background(theme.canvas.ignoresSafeArea())
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            Task { phase == .active ? await model.start() : await model.stop() }
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
                // A blink, not a flash: the frame darkens for a moment the way a
                // mechanical shutter does. Legible as confirmation, invisible as an
                // interruption.
                theme.shutterBlink
                    .opacity(model.blinkOpacity)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: Metrics.Viewfinder.cornerRadius))
            .opacity(model.isSwitching ? 0.55 : 1)
            .animation(Metrics.Motion.lensSwitch, value: model.isSwitching)

            if isAppearancePanelVisible {
                AppearancePanel(selection: $settings.appearance)
                    .padding(8)
            }
        }
    }
}

/// The only grid Onyx has, and the only view in the tree that uses it — folded in
/// here as private rather than kept as its own file, since it has exactly one
/// caller and nothing about it is independently reusable or independently tested.
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
