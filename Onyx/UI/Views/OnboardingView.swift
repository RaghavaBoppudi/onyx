import SwiftUI
import AVFoundation
import Photos

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSettingsPrompt = false
    
    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            
            VStack(spacing: Theme.Layout.paddingLarge) {
                Spacer()
                
                VStack(spacing: Theme.Layout.paddingSmall) {
                    Image("onyx-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .padding(.bottom, Theme.Layout.paddingSmall)
                    
                    Text("ONYX")
                        .font(.system(size: Theme.Typography.bodyBold * 2.2, weight: .light))
                        .foregroundColor(Theme.Color.text)
                        .tracking(8)
                    
                    Text("PURE IMAGE. ZERO PROCESSING.")
                        .font(.system(size: Theme.Typography.bodySmallBold, weight: .regular))
                        .foregroundColor(Theme.Color.accent)
                        .tracking(2)
                }
                
                VStack(spacing: Theme.Layout.paddingStandard) {
                    PermissionCard(icon: "onboarding-camera", title: "CAMERA", description: "Capture unprocessed photographs.")
                    PermissionCard(icon: "onboarding-gallery", title: "GALLERY", description: "Save and organize your photographs.")
                    PermissionCard(icon: "onboarding-location", title: "LOCATION", description: "Geotag your metadata.")
                }
                .padding(.vertical, Theme.Layout.paddingStandard)
                
                Spacer()
                
                Button(action: {
                    requestPermissionsAndProceed()
                }) {
                    Text("ALLOW ACCESS")
                        .font(.system(size: Theme.Typography.bodyBold, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Theme.Color.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(Theme.Color.text))
                }
                .padding(.horizontal, Theme.Layout.paddingLarge)
                .padding(.bottom, Theme.Layout.paddingLarge)
            }
            .blur(radius: showSettingsPrompt ? 10 : 0)
            
            if showSettingsPrompt {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
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
                            .background(Capsule().fill(Color.white))
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
    }
    
    private func requestPermissionsAndProceed() {
        Task {
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            
            var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if photoStatus == .notDetermined {
                photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            let photoGranted = (photoStatus == .authorized || photoStatus == .limited)
            
            _ = LocationProvider()
            
            await MainActor.run {
                if cameraGranted && photoGranted {
                    withAnimation { hasCompletedOnboarding = true }
                } else {
                    withAnimation(Theme.Physics.menuTransition) { showSettingsPrompt = true }
                }
            }
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: Theme.Layout.paddingStandard) {
            Image(icon)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: Theme.Typography.bodySemibold, weight: .medium))
                    .tracking(1)
                    .foregroundColor(Theme.Color.text)
                Text(description)
                    .font(.system(size: Theme.Typography.bodySmallBold, weight: .regular))
                    .foregroundColor(Theme.Color.text.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(Theme.Layout.paddingStandard)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .fill(Theme.Color.glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: Theme.Layout.borderWidth)
                )
        )
        .padding(.horizontal, Theme.Layout.paddingLarge)
    }
}
