import SwiftUI

struct BottomControlsView: View {
    let onShutterPress: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            ShutterButton(action: onShutterPress)
            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 56)
        .background(Color.black)
    }
}
