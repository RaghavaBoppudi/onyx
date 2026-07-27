import SwiftUI

struct TopControlsView: View {
    @Binding var isSettingsOpen: Bool
    @ObservedObject var viewModel: CameraViewModel
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
            
            Button(action: {
                viewModel.toggleGrid()
            }) {
                HStack(spacing: 2) {
                    Image(systemName: "rectangle.split.3x3")
                        .font(.system(size: Theme.Typography.iconStandard, weight: .bold))
                    
                    if viewModel.gridMode != .none {
                        Text(viewModel.gridMode == .thirds ? "1" : "2")
                            .font(.system(size: 12, weight: .black))
                    }
                }
                .foregroundColor(viewModel.gridMode == .none ? Theme.Color.text : Theme.Color.background)
                .frame(width: Theme.Layout.controlWidth, height: Theme.Layout.controlHeight)
                .background(
                    Capsule()
                        .fill(viewModel.gridMode != .none ? Theme.Color.accent : Theme.Color.glassBorderSubtle)
                )
                .rotationEffect(iconOrientation)
            }
        }
        .padding(.horizontal, Theme.Layout.paddingLarge)
        .padding(.top, Theme.Layout.paddingStandard)
        .padding(.bottom, Theme.Layout.paddingLarge)
        .background(Theme.Color.background)
    }
}
