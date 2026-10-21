import SwiftUI
import UIKit

struct LaunchGate<Content: View>: View {
    private let content: Content

    @State private var permissions = Permissions()
    @State private var admitted = false
    @State private var splashVisible = true
    @AppStorage("onyx.hasLaunched") private var hasLaunched = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if admitted {
                content
            } else {
                PermissionsScreen(permissions: permissions, onContinue: admit)
            }

            if splashVisible {
                SplashScreen()
                    .transition(.opacity)
            }
        }
        .task {
            admitted = permissions.requiredGranted
            let hold: Duration = hasLaunched ? .milliseconds(500) : .milliseconds(1400)
            hasLaunched = true
            await holdSplash(for: hold)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }

    private func admit() {
        guard !admitted else { return }
        withAnimation(.easeIn(duration: 0.1)) { splashVisible = true }
        admitted = true
        Task { await holdSplash(for: .milliseconds(500)) }
    }

    private func holdSplash(for duration: Duration) async {
        try? await Task.sleep(for: duration)
        withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.2)) { splashVisible = false }
    }
}

private struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Onyx")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-0.8)
        }
    }
}

private struct PermissionsScreen: View {
    let permissions: Permissions
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var device = CaptureAnimation.Device.phone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                CaptureAnimation(device: device)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Onyx needs a few permissions")
                        .font(.title2.weight(.semibold))
                    Text("Tap each one to allow it, in any order.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Permissions.Kind.allCases, id: \.self) { kind in
                        PermissionRow(
                            kind: kind,
                            isGranted: permissions.isGranted(kind),
                            isDenied: permissions.isDenied(kind)
                        ) {
                            select(kind)
                        }
                    }
                }
                .disabled(permissions.isRequesting)
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            device = CaptureAnimation.Device(ScreenClass.resolve(for: size))
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.onyxAccent)
            .disabled(!permissions.requiredGranted)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
    }

    private func select(_ kind: Permissions.Kind) {
        if permissions.isDenied(kind) {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else {
            Task { await permissions.request(kind) }
        }
    }
}

private struct PermissionRow: View {
    let kind: Permissions.Kind
    let isGranted: Bool
    let isDenied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: kind.symbol)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                    Text(kind.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isDenied && kind.isRequired {
                        Text("Onyx needs this to function")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: isGranted ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isGranted ? Color.onyxAccent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isGranted)
        .animation(.smooth(duration: 0.2), value: isGranted)
        .sensoryFeedback(.success, trigger: isGranted) { $1 }
        .sensoryFeedback(.warning, trigger: isDenied) { $1 }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed")
        .accessibilityHint(isGranted ? "" : isDenied ? "Opens Settings" : "Asks for permission")
    }
}

private extension Permissions.Kind {
    var symbol: String {
        switch self {
        case .camera: "camera"
        case .photos: "photo.on.rectangle"
        case .location: "location"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .camera: "Camera"
        case .photos: "Photos"
        case .location: "Location"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .camera: "Required to take photos."
        case .photos: "Required to save your photos."
        case .location: "Optional. Tags photos with where they were taken."
        }
    }
}
