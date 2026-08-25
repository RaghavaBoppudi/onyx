//  PermissionGateView.swift

import SwiftUI

struct PermissionGateView: View {
    @Environment(\.theme) private var theme

    let message: String
    let showsSettingsLink: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: Symbols.noPermission)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.iconInactive)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if showsSettingsLink, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(Typography.caption)
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }
}
