import SwiftUI

struct SettingsDropdownView: View {
    @Binding var selectedMode: ProcessingMode
    @Binding var isOpen: Bool
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 24) {
            Text(selectedMode.description)
                .font(.system(size: Theme.Typography.bodySmallBold, weight: .regular))
                .foregroundColor(Theme.Color.text.opacity(0.5))
                .multilineTextAlignment(.center)
                
            HStack(spacing: Theme.Layout.paddingSmall) {
                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                    Button(action: {
                        if selectedMode != mode {
                            hapticGenerator.selectionChanged()
                            selectedMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: Theme.Typography.bodySmallBold, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(selectedMode == mode ? Theme.Color.background : Theme.Color.text)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule()
                            .fill(selectedMode == mode ? Color.white : Color.white.opacity(0.15))
                    )
                }
            }
            .frame(maxWidth: 320)
        }
        .padding(.vertical, Theme.Layout.paddingStandard)
    }
}
