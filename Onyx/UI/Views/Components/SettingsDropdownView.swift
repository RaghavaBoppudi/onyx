import SwiftUI

struct SettingsDropdownView: View {
    @Binding var selectedMode: ProcessingMode
    @Binding var isOpen: Bool
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 32) {
            // Processing Mode Row
            VStack(spacing: 12) {
                Text("PIPELINE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.0)
                    .foregroundColor(Theme.Color.text.opacity(0.4))
                
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(selectedMode == mode ? Theme.Color.background : Theme.Color.text)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(selectedMode == mode ? Theme.Color.text : Theme.Color.glassBackground)
                        )
                    }
                }
            }
            
            // Appearance Row
            VStack(spacing: 12) {
                Text("APPEARANCE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.0)
                    .foregroundColor(Theme.Color.text.opacity(0.4))
                
                HStack(spacing: Theme.Layout.paddingSmall) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Button(action: {
                            if appTheme != theme {
                                hapticGenerator.selectionChanged()
                                appTheme = theme
                            }
                        }) {
                            Text(theme.rawValue)
                                .font(.system(size: Theme.Typography.bodySmallBold, weight: .bold))
                                .tracking(1.0)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(appTheme == theme ? Theme.Color.background : Theme.Color.text)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity) // Distributes equally
                        .background(
                            Capsule()
                                .fill(appTheme == theme ? Theme.Color.text : Theme.Color.glassBackground)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, Theme.Layout.paddingStandard)
    }
}
