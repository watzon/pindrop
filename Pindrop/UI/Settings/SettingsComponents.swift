//
//  SettingsComponents.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import SwiftUI

/// Card chrome still used by the main-window Models page (`ModelsSettingsView`).
/// Settings panes no longer use this component.
struct SettingsCard<Content: View, HeaderAccessory: View>: View {
    let title: String
    let icon: String
    let detail: String?
    @ViewBuilder let headerAccessory: HeaderAccessory
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        detail: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    init(
        title: String,
        icon: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        self.init(title: title, icon: icon, detail: detail, headerAccessory: { EmptyView() }, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .fill(AppColors.accentBackground)
                            .frame(width: 28, height: 28)

                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)

                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 0)

                headerAccessory
            }

            content
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(AppColors.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(AppTheme.Shadow.sm)
    }
}
