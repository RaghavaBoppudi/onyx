import SwiftUI

struct SettingsDropdownView: View {
    @Binding var selectedMode: ProcessingMode
    @Binding var isOpen: Bool
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(alignment: .center, spacing: Theme.Layout.paddingStandard) {
            
            // Minimalist Close Target
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(Theme.Physics.menuTransition) { isOpen = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.Typography.iconLarge))
                        .foregroundColor(Theme.Color.glassBorderStrong)
                        .padding(.bottom, -8)
                }
            }
            
            HStack(spacing: Theme.Layout.paddingSmall) {
                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                    Button(action: {
                        if selectedMode != mode {
                            hapticGenerator.selectionChanged()
                            selectedMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: Theme.Typography.bodySmallBold, weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(selectedMode == mode ? Theme.Color.background : Theme.Color.text)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule()
                            .fill(selectedMode == mode ? Color.white : Color.white.opacity(0.1))
                    )
                }
            }
            
            Text(selectedMode.description)
                .font(.system(size: Theme.Typography.bodySmallBold, weight: .regular))
                .foregroundColor(Theme.Color.text.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Layout.paddingStandard)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: Theme.Layout.borderWidth)
                )
        )
    }
}
