import SwiftUI

struct LooksToggle: View {
    let currentLookName: String
    @Binding var isBrowsing: Bool

    var body: some View {
        Picker("Looks", selection: Binding(
            get: { isBrowsing ? 1 : 0 },
            set: { newValue in
                guard (newValue == 1) != isBrowsing else { return }
                Haptics.shared.fire(.toggle)
                isBrowsing = newValue == 1
            }
        )) {
            Text(currentLookName).tag(0)
            Text("Looks").tag(1)
        }
        .pickerStyle(.segmented)
        .frame(width: Metrics.LooksToggle.width)
    }
}
