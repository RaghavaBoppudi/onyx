import SwiftUI

struct LensSelectorView: View {
    let availableLenses: [Lens]
    let currentLens: Lens?
    let iconOrientation: Angle
    let onSelectLens: (Lens) -> Void
    
    private let hapticGenerator = UISelectionFeedbackGenerator()
    
    var body: some View {
        HStack(spacing: Theme.Layout.Lens.itemSpacing) {
            ForEach(availableLenses, id: \.label) { lens in
                let isSelected = lens == currentLens
                
                Button(action: {
                    if !isSelected {
                        hapticGenerator.selectionChanged()
                        onSelectLens(lens)
                    }
                }) {
                    Text(lens.label)
                        .font(.system(size: Theme.Typography.bodyBold, weight: .bold))
                        .foregroundColor(isSelected ? Theme.Color.accent : Color.white)
                        .opacity(isSelected ? 1.0 : 0.4)
                        .shadow(color: Color.black.opacity(0.8), radius: 2, x: 0, y: 1)
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
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: Theme.Layout.borderWidth)
                )
        )
    }
}
