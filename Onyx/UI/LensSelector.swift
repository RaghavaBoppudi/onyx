import SwiftUI

struct LensSelector: View {
    let lenses: [Lens]
    let selectedID: String?
    let onSelect: (Lens) -> Void

    @State private var pendingID: String?

    private var displayedID: String? { pendingID ?? selectedID }

    private var totalWidth: CGFloat {
        guard !lenses.isEmpty else { return 0 }
        return CGFloat(lenses.count) * Metrics.LensSelector.itemWidth
            + CGFloat(lenses.count - 1) * Metrics.LensSelector.itemSpacing
    }

    var body: some View {
        Group {
            if selectedID == nil {
                Color.clear
                    .frame(width: totalWidth, height: Metrics.LensSelector.pillHeight)
            } else {
                SelectorDial(
                    items: lenses,
                    selectedID: displayedID,
                    accessibilityNoun: "lens",
                    glassNamespaceID: "lens.active",
                    label: { $0.label },
                    onSelect: select
                )
                .onChange(of: selectedID) { _, _ in
                    pendingID = nil
                }
            }
        }
    }

    private func select(_ lens: Lens) {
        guard lens.id != displayedID else { return }
        pendingID = lens.id
        onSelect(lens)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if pendingID == lens.id { pendingID = nil }
        }
    }
}
