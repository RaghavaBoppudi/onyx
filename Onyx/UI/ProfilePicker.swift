import SwiftUI

struct ProfilePicker: View {
    let model: CameraModel
    var compact = false

    var body: some View {
        Picker("Capture", selection: selection) {
            ForEach(CaptureProfile.allCases) { profile in
                segment(for: profile).tag(profile)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: compact ? 96 : .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!model.canChangeProfile)
    }

    @ViewBuilder
    private func segment(for profile: CaptureProfile) -> some View {
        if compact {
            Label(profile.title, systemImage: profile.symbol)
                .labelStyle(.iconOnly)
        } else {
            Text(profile.title)
        }
    }

    private var selection: Binding<CaptureProfile> {
        Binding(
            get: { model.profile },
            set: { model.requestProfile($0) }
        )
    }
}
