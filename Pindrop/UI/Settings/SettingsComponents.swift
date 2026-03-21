//
//  SettingsComponents.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import SwiftUI

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

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(AppColors.divider)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct SettingsInfoBanner: View {
    let icon: String
    let text: String
    let tint: Color
    let background: Color
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        text: String,
        tint: Color,
        background: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.text = text
        self.tint = tint
        self.background = background
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SettingsTag: View {
    let title: String
    let tint: Color
    let background: Color

    var body: some View {
        Text(title)
            .font(AppTypography.tiny)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }
}

struct SettingsCardActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}
