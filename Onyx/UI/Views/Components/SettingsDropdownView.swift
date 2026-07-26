import SwiftUI

struct SettingsDropdownView: View {
    @Binding var selectedMode: ProcessingMode
    @Binding var isOpen: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 0) {
                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedMode = mode
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedMode == mode ? Theme.background : Theme.text)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedMode == mode ? Theme.accent : Color.clear)
                            )
                    }
                }
            }
            
            Text(selectedMode.description)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .liquidGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), isBordered: true)
        )
        .padding(.horizontal, 16)
    }
}
