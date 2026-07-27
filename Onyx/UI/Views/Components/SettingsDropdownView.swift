import SwiftUI

struct SettingsDropdownView: View {
    @Binding var selectedMode: ProcessingMode
    @Binding var isOpen: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: Theme.Layout.paddingStandard) {
            HStack(spacing: 0) {
                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedMode = mode
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: Theme.Typography.bodySmallBold, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedMode == mode ? Theme.Color.background : Theme.Color.text)
                            .padding(.vertical, Theme.Layout.paddingSmall)
                            .background(
                                Capsule()
                                    .fill(selectedMode == mode ? Theme.Color.accent : SwiftUI.Color.clear)
                            )
                    }
                }
            }
            
            Text(selectedMode.description)
                .font(.system(size: Theme.Typography.bodySemibold, weight: .semibold))
                .foregroundColor(Theme.Color.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
        }
        .padding(Theme.Layout.paddingStandard)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .fill(Theme.Color.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: Theme.Layout.borderWidth)
                )
        )
    }
}
