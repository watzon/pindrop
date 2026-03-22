//
//  ThemeSettingsView.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var settings: SettingsStore

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.md),
        GridItem(.flexible(), spacing: AppTheme.Spacing.md),
        GridItem(.flexible(), spacing: AppTheme.Spacing.md),
    ]

    private var modeBinding: Binding<PindropThemeMode> {
        Binding(
            get: { settings.selectedThemeMode },
            set: { settings.selectedThemeMode = $0 }
        )
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            modeCard
            presetCard(variant: .light)
            presetCard(variant: .dark)
        }
        .themeRefresh()
    }

    private var modeCard: some View {
        SettingsCard(
            title: "Theme",
            icon: "paintbrush.pointed",
            detail: "Choose how Pindrop follows system appearance, then mix curated light and dark palettes."
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Picker("Theme mode", selection: modeBinding) {
                    ForEach(PindropThemeMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.theme.mode")

                HStack(spacing: AppTheme.Spacing.md) {
                    ThemePreviewPane(
                        title: "Light Preview",
                        preset: settings.selectedLightThemePreset,
                        variant: .light,
                        isActive: modeBinding.wrappedValue != .dark
                    )

                    ThemePreviewPane(
                        title: "Dark Preview",
                        preset: settings.selectedDarkThemePreset,
                        variant: .dark,
                        isActive: modeBinding.wrappedValue != .light
                    )
                }

                SettingsInfoBanner(
                    icon: "sparkles",
                    text: "Theme changes apply live across the workspace, settings, note editor, and floating indicators.",
                    tint: AppColors.accent,
                    background: AppColors.accentBackground
                )
            }
        }
    }

    private func presetCard(variant: PindropThemeVariant) -> some View {
        let isLight = variant == .light

        return SettingsCard(
            title: isLight ? "Light Theme" : "Dark Theme",
            icon: isLight ? "sun.max" : "moon.stars",
            detail: isLight
                ? "Choose the daytime shell used in light mode."
                : "Choose the low-glare shell used in dark mode."
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(PindropThemePresetCatalog.presets) { preset in
                    ThemePresetTile(
                        preset: preset,
                        variant: variant,
                        isSelected: selectedPresetID(for: variant) == preset.id,
                        action: { selectPreset(preset.id, for: variant) }
                    )
                }
            }
        }
    }

    private func selectedPresetID(for variant: PindropThemeVariant) -> String {
        switch variant {
        case .light:
            return settings.lightThemePresetID
        case .dark:
            return settings.darkThemePresetID
        }
    }

    private func selectPreset(_ presetID: String, for variant: PindropThemeVariant) {
        withAnimation(AppTheme.Animation.smooth) {
            switch variant {
            case .light:
                settings.lightThemePresetID = presetID
            case .dark:
                settings.darkThemePresetID = presetID
            }
        }
    }
}

private struct ThemePreviewPane: View {
    let title: String
    let preset: PindropThemePreset
    let variant: PindropThemeVariant
    let isActive: Bool

    private var profile: PindropThemeProfile {
        preset.profile(for: variant)
    }

    var body: some View {
        let background = Color(nsColor: NSColor(pindropHex: profile.backgroundHex) ?? .windowBackgroundColor)
        let foreground = Color(nsColor: NSColor(pindropHex: profile.foregroundHex) ?? .labelColor)
        let accent = Color(nsColor: NSColor(pindropHex: profile.accentHex) ?? .controlAccentColor)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.caption)
                        .foregroundStyle(foreground.opacity(0.72))
                    Text(preset.title)
                        .font(AppTypography.headline)
                        .foregroundStyle(foreground)
                }

                Spacer()

                if isActive {
                    SettingsTag(
                        title: "Active",
                        tint: accent,
                        background: accent.opacity(0.14)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(foreground.opacity(0.08))
                    .frame(height: 34)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 2).fill(foreground).frame(width: 42, height: 4)
                        }
                        .padding(.horizontal, 10)
                    }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(foreground.opacity(0.06))
                    .frame(height: 66)
                    .overlay(alignment: .bottomTrailing) {
                        Capsule()
                            .fill(accent)
                            .frame(width: 52, height: 8)
                            .padding(10)
                    }
            }

            Text(preset.summary)
                .font(AppTypography.caption)
                .foregroundStyle(foreground.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(foreground.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ThemePresetTile: View {
    let preset: PindropThemePreset
    let variant: PindropThemeVariant
    let isSelected: Bool
    let action: () -> Void

    private var profile: PindropThemeProfile {
        preset.profile(for: variant)
    }

    var body: some View {
        let background = Color(nsColor: NSColor(pindropHex: profile.backgroundHex) ?? .windowBackgroundColor)
        let foreground = Color(nsColor: NSColor(pindropHex: profile.foregroundHex) ?? .labelColor)
        let accent = Color(nsColor: NSColor(pindropHex: profile.accentHex) ?? .controlAccentColor)

        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(preset.badgeText)
                        .font(AppTypography.caption)
                        .foregroundStyle(Color(nsColor: NSColor(pindropHex: preset.badgeForegroundHex) ?? .labelColor))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Color(nsColor: NSColor(pindropHex: preset.badgeBackgroundHex) ?? .windowBackgroundColor),
                            in: Capsule()
                        )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
                }

                Text(preset.title)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(foreground)

                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Circle().fill(foreground.opacity(0.18)).frame(width: 8, height: 8)
                    Circle().fill(foreground.opacity(0.1)).frame(width: 8, height: 8)
                }

                Text(preset.summary)
                    .font(AppTypography.tiny)
                    .foregroundStyle(foreground.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(background, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.accent : foreground.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0), radius: 10, y: 4)
            .scaleEffect(isSelected ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.theme.\(variant.rawValue).preset.\(preset.id)")
    }
}

#Preview {
    ThemeSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 900)
}
