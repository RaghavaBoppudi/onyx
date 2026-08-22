import SwiftUI

struct SettingsDropdownView: View {
    @Binding var isOpen: Bool
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("APPEARANCE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.0)
                    .foregroundColor(Color.white.opacity(0.45))
                
                HStack(spacing: Theme.Layout.paddingSmall) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        let isSelected = (appTheme == theme)
                        
                        Button(action: {
                            if appTheme != theme {
                                HapticManager.shared.playSelection()
                                appTheme = theme
                            }
                        }) {
                            Text(theme.rawValue)
                                .font(.system(size: Theme.Typography.bodySmallBold, weight: .bold))
                                .tracking(1.0)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(isSelected ? .black : .white)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white : Color.white.opacity(0.12))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Layout.paddingStandard)
        .padding(.vertical, Theme.Layout.paddingStandard)
        .glassEffect(in: .rect(cornerRadius: Theme.Layout.cornerRadius - 4))
    }
}
