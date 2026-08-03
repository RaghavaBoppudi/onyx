import SwiftUI

struct ExposureBarView: View {
    @Binding var currentEV: Float
    private let evSteps: [Float] = [-2.0, -1.0, 0.0, +1.0, +2.0]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(evSteps, id: \.self) { ev in
                Button(action: {
                    HapticManager.shared.playSelection()
                    currentEV = ev
                }) {
                    Text(formatEV(ev))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(currentEV == ev ? Theme.Color.background : Theme.Color.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(currentEV == ev ? Theme.Color.text : Theme.Color.glassBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Theme.Color.background.opacity(0.8))
                .overlay(Capsule().strokeBorder(Theme.Color.glassBorderSubtle, lineWidth: 0.5))
        )
    }
    
    private func formatEV(_ value: Float) -> String {
        if value > 0 { return "+\(value)" }
        if value == 0 { return "0.0" }
        return "\(value)"
    }
}
