//
//  ThemeSettingsView.swift
//  Pindrop
//
//  Created on 2026-03-20.
//

import AppKit
import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsPaneStack {
            // Mode
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Theme Mode", locale: locale))
                } control: {
                    HStack(spacing: 6) {
                        ForEach(PindropThemeMode.allCases) { mode in
                            FilterChip(
                                title: mode.title(locale: locale),
                                isSelected: settings.selectedThemeMode == mode
                            ) {
                                settings.selectedThemeMode = mode
                            }
                            .accessibilityIdentifier("settings.theme.mode.\(mode.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("settings.theme.mode")
                }
            }

            // Theme presets (6 + legacy-while-active)
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("Theme preset", locale: locale))
                        .font(AppTypography.labelStrong)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)
                        .padding(.top, SettingsLayoutMetrics.rowVerticalPadding)

                    FlowPresetChips(
                        presets: presetsForActiveVariant,
                        variant: activeVariantForSwatches,
                        selectedID: activePresetID,
                        onSelect: { selectPreset($0) }
                    )
                    .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)

                    Text(localized("Presets recolor the accent and grounds. Text contrast is validated automatically.", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SettingsLayoutMetrics.rowHorizontalPadding)
                        .padding(.bottom, SettingsLayoutMetrics.rowVerticalPadding)
                }
            }

            // Recording indicator
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Recording indicator", locale: locale))
                } control: {
                    HStack(spacing: 6) {
                        ForEach(FloatingIndicatorType.allCases) { type in
                            FilterChip(
                                title: type.displayName(locale: locale),
                                isSelected: settings.selectedFloatingIndicatorType == type
                            ) {
                                settings.selectedFloatingIndicatorType = type
                            }
                            .accessibilityIdentifier("settings.floatingIndicator.\(type.rawValue)")
                        }
                    }
                }
            }

            // Sidebar position (Decision 4 — keep)
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Sidebar Position", locale: locale))
                } control: {
                    HStack(spacing: 6) {
                        FilterChip(
                            title: localized("Left", locale: locale),
                            systemImage: "sidebar.left",
                            isSelected: settings.selectedSidebarPosition == .leading
                        ) {
                            settings.selectedSidebarPosition = .leading
                        }
                        FilterChip(
                            title: localized("Right", locale: locale),
                            systemImage: "sidebar.right",
                            isSelected: settings.selectedSidebarPosition == .trailing
                        ) {
                            settings.selectedSidebarPosition = .trailing
                        }
                    }
                    .accessibilityIdentifier("settings.picker.sidebarPosition")
                }
            }
        }
        .themeRefresh()
    }

    private var activeVariantForSwatches: PindropThemeVariant {
        switch settings.selectedThemeMode {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .dark : .light
        }
    }

    private var activePresetID: String {
        switch activeVariantForSwatches {
        case .light: return settings.lightThemePresetID
        case .dark: return settings.darkThemePresetID
        }
    }

    private var presetsForActiveVariant: [PindropThemePreset] {
        SettingsThemePresetPresentation.presetsForPicker(selectedID: activePresetID)
    }

    private func selectPreset(_ presetID: String) {
        // Apply to the active variant; when System, update both so mode flips stay consistent.
        switch settings.selectedThemeMode {
        case .light:
            settings.lightThemePresetID = presetID
        case .dark:
            settings.darkThemePresetID = presetID
        case .system:
            settings.lightThemePresetID = presetID
            settings.darkThemePresetID = presetID
        }
        PindropThemeController.shared.refresh()
    }
}

// MARK: - Wrapping preset chips

private struct FlowPresetChips: View {
    let presets: [PindropThemePreset]
    let variant: PindropThemeVariant
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        // Simple wrap via LazyVGrid flexible columns (2–3 depending on width).
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 120), spacing: 8),
            ],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(presets) { preset in
                SettingsThemePresetChip(
                    preset: preset,
                    variant: variant,
                    isSelected: selectedID == preset.id
                ) {
                    onSelect(preset.id)
                }
            }
        }
    }
}

#Preview {
    ThemeSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 640)
        .background(AppColors.windowBackground)
        .themeRefresh()
}
