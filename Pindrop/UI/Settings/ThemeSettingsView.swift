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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        Form {
            Section {
                Picker(localized("Theme Mode", locale: locale), selection: themeModeBinding) {
                    ForEach(PindropThemeMode.allCases) { mode in
                        Label(mode.title(locale: locale), systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.theme.mode")

                if settings.selectedThemeMode != .dark {
                    presetGrid(variant: .light)
                }

                if settings.selectedThemeMode != .light {
                    presetGrid(variant: .dark)
                }
            } header: {
                Text(localized("Theme", locale: locale))
            } footer: {
                Text(localized("Theme changes apply live across the workspace, settings, note editor, and floating indicators.", locale: locale))
            }

            Section {
                Picker(
                    localized("Sidebar Position", locale: locale),
                    selection: sidebarPositionBinding
                ) {
                    Label(localized("Left", locale: locale), systemImage: "sidebar.left")
                        .tag(SidebarPosition.leading)
                    Label(localized("Right", locale: locale), systemImage: "sidebar.right")
                        .tag(SidebarPosition.trailing)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.picker.sidebarPosition")
            } header: {
                Text(localized("Main Window", locale: locale))
            } footer: {
                Text(localized("Choose which edge of the main window holds the navigation sidebar.", locale: locale))
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(FloatingIndicatorType.allCases) { type in
                        FloatingIndicatorStyleTile(
                            type: type,
                            isSelected: settings.selectedFloatingIndicatorType == type
                        ) {
                            settings.selectedFloatingIndicatorType = type
                        }
                    }
                }
            } header: {
                Text(localized("Floating Indicator", locale: locale))
            } footer: {
                Text(localized("Choose how recording and processing status appears while you work.", locale: locale))
            }
        }
        .formStyle(.grouped)
        .themeRefresh()
    }

    private var themeModeBinding: Binding<PindropThemeMode> {
        Binding(
            get: { settings.selectedThemeMode },
            set: { settings.selectedThemeMode = $0 }
        )
    }

    private var sidebarPositionBinding: Binding<SidebarPosition> {
        Binding(
            get: { settings.selectedSidebarPosition },
            set: { settings.selectedSidebarPosition = $0 }
        )
    }

    @ViewBuilder
    private func presetGrid(variant: PindropThemeVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                variant == .light
                    ? localized("Light Theme", locale: locale)
                    : localized("Dark Theme", locale: locale)
            )
            .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(PindropThemePresetCatalog.presets) { preset in
                    ThemePresetTile(
                        preset: preset,
                        variant: variant,
                        isSelected: selectedPresetID(for: variant) == preset.id
                    ) {
                        selectPreset(preset.id, for: variant)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func selectedPresetID(for variant: PindropThemeVariant) -> String {
        switch variant {
        case .light: settings.lightThemePresetID
        case .dark: settings.darkThemePresetID
        }
    }

    private func selectPreset(_ presetID: String, for variant: PindropThemeVariant) {
        switch variant {
        case .light:
            settings.lightThemePresetID = presetID
        case .dark:
            settings.darkThemePresetID = presetID
        }
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                HStack(spacing: 6) {
                    swatch(profile.groundHex)
                    swatch(profile.pageHex)
                    swatch(profile.accentHex)
                }

                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.theme.\(variant.rawValue).preset.\(preset.id)")
        .accessibilityValue(isSelected ? "selected" : "")
    }

    private func swatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(nsColor: NSColor(pindropHex: hex) ?? .controlColor))
            .frame(height: 20)
    }
}

private struct FloatingIndicatorStyleTile: View {
    @Environment(\.locale) private var locale

    let type: FloatingIndicatorType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                indicatorPreview
                    .frame(height: 36)

                Text(type.displayName(locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(type.description(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.floatingIndicator.\(type.rawValue)")
        .accessibilityValue(isSelected ? "selected" : "")
    }

    @ViewBuilder
    private var indicatorPreview: some View {
        switch type {
        case .pill:
            Capsule()
                .fill(.secondary.opacity(0.22))
                .frame(width: 82, height: 28)
                .overlay {
                    HStack(spacing: 4) {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        Capsule().fill(.secondary).frame(width: 34, height: 4)
                    }
                }
        case .orb:
            Circle()
                .fill(.secondary.opacity(0.22))
                .frame(width: 34, height: 34)
                .overlay {
                    Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                }
        }
    }
}

#Preview {
    ThemeSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 640)
}
