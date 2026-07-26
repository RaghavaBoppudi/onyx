import SwiftUI

struct TopControlsView: View {
    @Binding var isSettingsOpen: Bool
    let iconOrientation: Angle
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation(Theme.Physics.menuTransition) {
                    isSettingsOpen.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: Theme.Typography.iconStandard, weight: .bold))
                    .foregroundColor(isSettingsOpen ? Theme.Color.background : Theme.Color.text)
                    .frame(width: Theme.Layout.controlWidth, height: Theme.Layout.controlHeight)
                    .background(
                        Capsule()
                            .fill(isSettingsOpen ? Theme.Color.accent : Theme.Color.glassBorderSubtle)
                    )
                    .rotationEffect(iconOrientation)
            }
            
            Spacer()
        }
        .padding(.horizontal, Theme.Layout.paddingLarge)
        .padding(.top, Theme.Layout.paddingStandard)
        .padding(.bottom, Theme.Layout.paddingLarge)
        .background(Theme.Color.background)
    }
}
