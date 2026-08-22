import SwiftUI

struct LensSelectorView: View {
    let availableLenses: [Lens]
    let currentLens: Lens?
    let iconOrientation: Angle
    let onSelectLens: (Lens) -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            ForEach(availableLenses, id: \.label) { lens in
                let isSelected = lens == currentLens
                
                Button(action: {
                    if !isSelected {
                        HapticManager.shared.playSelection()
                        onSelectLens(lens)
                    }
                }) {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(isSelected ? Theme.Color.text : Color.clear)
                            .frame(width: 4, height: 4)
                        
                        Text(lens.label)
                            .font(.system(size: Theme.Typography.bodyBold, weight: .bold))
                            .foregroundColor(Theme.Color.text)
                            .opacity(isSelected ? 1.0 : 0.4)
                    }
                    .frame(width: Theme.Layout.Lens.buttonWidth, height: Theme.Layout.Lens.buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .rotationEffect(iconOrientation)
                .animation(.easeOut(duration: 0.2), value: isSelected)
            }
        }
        .padding(.horizontal, Theme.Layout.paddingStandard)
        .padding(.vertical, Theme.Layout.Lens.padding)
    }
}
