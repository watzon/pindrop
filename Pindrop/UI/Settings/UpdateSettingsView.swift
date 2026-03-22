//
//  UpdateSettingsView.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import SwiftUI

struct UpdateSettingsView: View {
    @State private var updateService = UpdateService()
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    @Environment(\.locale) private var locale
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            SettingsCard(
                title: localized("Updates", locale: locale),
                icon: "arrow.triangle.2.circlepath",
                detail: localized("Keep Pindrop current automatically, or trigger a manual check whenever you want.", locale: locale)
            ) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    SettingsToggleRow(
                        title: localized("Automatic updates", locale: locale),
                        detail: localized("Automatically check for new versions in the background.", locale: locale),
                        isOn: $automaticallyCheckForUpdates
                    )
                    .onChange(of: automaticallyCheckForUpdates) { _, newValue in
                        updateService.automaticallyChecksForUpdates = newValue
                    }

                    SettingsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Check for updates", locale: locale))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(localized("Manually check for new versions now.", locale: locale))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Button(localized("Check Now", locale: locale)) {
                            updateService.checkForUpdates()
                        }
                        .disabled(!updateService.canCheckForUpdates)
                    }
                }
            }
        }
        .onAppear {
            updateService.automaticallyChecksForUpdates = automaticallyCheckForUpdates
        }
    }
}

#Preview {
    UpdateSettingsView()
        .padding()
        .frame(width: 500)
}
