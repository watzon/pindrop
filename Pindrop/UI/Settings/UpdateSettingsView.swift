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
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            SettingsCard(
                title: "Updates",
                icon: "arrow.triangle.2.circlepath",
                detail: "Keep Pindrop current automatically, or trigger a manual check whenever you want."
            ) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    SettingsToggleRow(
                        title: "Automatic updates",
                        detail: "Automatically check for new versions in the background.",
                        isOn: $automaticallyCheckForUpdates
                    )
                    .onChange(of: automaticallyCheckForUpdates) { _, newValue in
                        updateService.automaticallyChecksForUpdates = newValue
                    }

                    SettingsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for updates")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Manually check for new versions now.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Button("Check Now") {
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
