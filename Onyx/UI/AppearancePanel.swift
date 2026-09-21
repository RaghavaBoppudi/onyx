import SwiftUI

struct AppearancePanel: View {
    @Environment(\.theme) private var theme
    @Binding var selection: AppearanceMode

    var body: some View {
        VStack(spacing: Metrics.Panel.padding) {
            Text("APPEARANCE")
                .font(Typography.panelHeader)
                .tracking(1.6)
                .foregroundStyle(theme.secondary)

            Picker("Appearance", selection: $selection.hapticFeedback(.selection)) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(Metrics.Panel.padding + 4)
        .frame(maxWidth: .infinity)
        .onyxGlass(in: .rect(cornerRadius: Metrics.Panel.cornerRadius))
        .transition(.opacity)
    }
}
