import SwiftUI
import AVFoundation
import Photos

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0
    
    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            
            VStack(spacing: Theme.Layout.paddingLarge) {
                Spacer()
                
                Image("onyx-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .padding(.bottom, Theme.Layout.paddingStandard)
                
                if currentStep == 0 {
                    VStack(spacing: 8) {
                        Text("ONYX")
                            .font(.system(size: Theme.Typography.bodyBold * 2.2, weight: .light))
                            .foregroundColor(Theme.Color.text)
                            .tracking(8)
                        
                        Text("PURE IMAGE. ZERO PROCESSING.")
                            .font(.system(size: Theme.Typography.bodySmallBold, weight: .regular))
                            .foregroundColor(Theme.Color.accent)
                            .tracking(2)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    VStack(spacing: Theme.Layout.paddingStandard) {
                        Text("ONYX NEEDS A FEW PERMISSIONS")
                            .font(.system(size: Theme.Typography.bodyBold * 1.2, weight: .medium))
                            .foregroundColor(Theme.Color.text)
                            .tracking(1)
                            .padding(.bottom, Theme.Layout.paddingSmall)
                        
                        PermissionCard(icon: "onboarding-camera", title: "CAMERA", description: "Capture unprocessed photographs.")
                        PermissionCard(icon: "onboarding-gallery", title: "GALLERY", description: "Save and organize your photographs.")
                        PermissionCard(icon: "onboarding-location", title: "LOCATION", description: "Geotag your metadata.")
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                Spacer()
                
                Button(action: {
                    if currentStep == 0 {
                        withAnimation(Theme.Physics.menuTransition) {
                            currentStep = 1
                        }
                    } else {
                        requestPermissionsAndProceed()
                    }
                }) {
                    Text(currentStep == 0 ? "ENTER" : "AUTHORIZE")
                        .font(.system(size: Theme.Typography.bodyBold, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Theme.Color.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(Color.white))
                }
                .padding(.horizontal, Theme.Layout.paddingLarge)
                .padding(.bottom, Theme.Layout.paddingLarge)
            }
        }
    }
    
    private func requestPermissionsAndProceed() {
        Task {
            await AVCaptureDevice.requestAccess(for: .video)
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            
            _ = LocationProvider()
            
            await MainActor.run {
                withAnimation {
                    hasCompletedOnboarding = true
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
