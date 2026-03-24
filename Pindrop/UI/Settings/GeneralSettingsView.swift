//
//  GeneralSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale
    @State private var showingResetConfirmation = false
    @State private var availableInputDevices: [AudioInputDevice] = []
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            outputSection
            languageSection
            audioInputSection
            floatingIndicatorSection
            dictionarySection
            interfaceSection
            resetSection
        }
    }

    private var languageSection: some View {
        SettingsCard(
            title: localized("Language", locale: locale),
            icon: "globe",
            detail: localized(
                "Choose languages for the interface and for dictation. Automatic follows the system.",
                locale: locale
            )
        ) {
            SelectField(
                options: languageOptions,
                selection: selectedLanguageSelection,
                placeholder: AppLanguage.automatic.displayName(locale: locale)
            )
            .frame(maxWidth: 320, alignment: .leading)
        }
    }
    
    private var outputSection: some View {
        SettingsCard(
            title: localized("Output", locale: locale),
            icon: "doc.on.clipboard",
            detail: localized("Choose how dictated text lands, then tune the final insertion behavior.", locale: locale)
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                ForEach(OutputOption.allCases) { option in
                    OutputOptionRow(
                        option: option,
                        isSelected: settings.outputMode == option.rawValue,
                        onSelect: { settings.outputMode = option.rawValue }
                    )
                }
                
                SettingsDivider()

                SettingsToggleRow(
                    title: localized("Add trailing space", locale: locale),
                    detail: localized("Append a space after each transcription for seamless dictation.", locale: locale),
                    isOn: $settings.addTrailingSpace,
                    accessibilityIdentifier: "settings.toggle.addTrailingSpace"
                )

                if AppTestMode.isRunningUITests {
                    Text(settings.addTrailingSpace ? localized("On", locale: locale) : localized("Off", locale: locale))
                        .font(AppTypography.tiny)
                        .foregroundStyle(AppColors.textTertiary)
                        .accessibilityIdentifier("settings.toggle.addTrailingSpace.state")
                }
            }
        }
    }
    
    private var interfaceSection: some View {
        SettingsCard(
            title: localized("Interface", locale: locale),
            icon: "macwindow",
            detail: localized("Control how Pindrop appears in macOS and whether it starts with your desktop session.", locale: locale)
        ) {
            VStack(spacing: AppTheme.Spacing.lg) {
                SettingsToggleRow(
                    title: localized("Launch at login", locale: locale),
                    detail: localized("Automatically start Pindrop when you sign in.", locale: locale),
                    isOn: $settings.launchAtLogin,
                    accessibilityIdentifier: "settings.toggle.launchAtLogin"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: localized("Show in Dock", locale: locale),
                    detail: localized("Display Pindrop in the Dock instead of running only as a menu bar app.", locale: locale),
                    isOn: $settings.showInDock,
                    accessibilityIdentifier: "settings.toggle.showInDock"
                )
            }
        }
    }

    private var floatingIndicatorSection: some View {
        FloatingIndicatorSettingsCard(settings: settings)
    }

    private var dictionarySection: some View {
        SettingsCard(
            title: localized("Dictionary", locale: locale),
            icon: "text.book.closed",
            detail: localized("Let Pindrop quietly learn vocabulary from the corrections you make over time.", locale: locale)
        ) {
            SettingsToggleRow(
                title: localized("Learn corrected words automatically", locale: locale),
                detail: localized("Add words you manually correct into your vocabulary for future transcriptions.", locale: locale),
                isOn: $settings.automaticDictionaryLearningEnabled,
                accessibilityIdentifier: "settings.toggle.automaticDictionaryLearningEnabled"
            )
        }
    }

    private var audioInputSection: some View {
        SettingsCard(
            title: localized("Audio Input", locale: locale),
            icon: "mic",
            detail: localized("Choose which microphone Pindrop should use for dictation and how it behaves while recording.", locale: locale)
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    SelectField(
                        options: audioInputOptions,
                        selection: selectedAudioInputSelection,
                        placeholder: localized("System Default", locale: locale)
                    )
                    .frame(maxWidth: 300, alignment: .leading)

                    Button(localized("Refresh", locale: locale)) {
                        refreshInputDevices()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: localized("Pause media during transcription", locale: locale),
                    detail: localized("Temporarily pause active media playback while dictation is recording.", locale: locale),
                    isOn: $settings.pauseMediaOnRecording,
                    accessibilityIdentifier: "settings.toggle.pauseMediaOnRecording"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: localized("Mute system audio during recording", locale: locale),
                    detail: localized("Temporarily mute speaker output while dictation is recording.", locale: locale),
                    isOn: $settings.muteAudioDuringRecording,
                    accessibilityIdentifier: "settings.toggle.muteAudioDuringRecording"
                )
            }
        }
        .onAppear {
            refreshInputDevices()
            if settings.pauseMediaOnRecording && settings.muteAudioDuringRecording {
                settings.muteAudioDuringRecording = false
            }
        }
        .onChange(of: settings.pauseMediaOnRecording) { _, newValue in
            if newValue {
                settings.muteAudioDuringRecording = false
            }
        }
        .onChange(of: settings.muteAudioDuringRecording) { _, newValue in
            if newValue {
                settings.pauseMediaOnRecording = false
            }
        }
    }
    
    private var resetSection: some View {
        SettingsCard(
            title: localized("Reset", locale: locale),
            icon: "arrow.counterclockwise",
            detail: localized("Start fresh when you want to clear preferences, onboarding state, and saved credentials.", locale: locale)
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Reset all settings", locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized("Clears preferences and restarts onboarding", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Text(localized("Reset", locale: locale))
                }
                .buttonStyle(.bordered)
            }
        }
        .alert(localized("Reset All Settings?", locale: locale), isPresented: $showingResetConfirmation) {
            Button(localized("Cancel", locale: locale), role: .cancel) { }
            Button(localized("Reset", locale: locale), role: .destructive) {
                settings.resetAllSettings()
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(localized("This will clear all your settings, including API keys, hotkeys, and model preferences. The app will quit and show onboarding again on next launch.", locale: locale))
        }
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.inputDevices()
    }
}

private extension GeneralSettingsView {
    var audioInputOptions: [SelectFieldOption] {
        var options = [SelectFieldOption(id: "", displayName: localized("System Default", locale: locale))]

        if !settings.selectedInputDeviceUID.isEmpty,
           !availableInputDevices.contains(where: { $0.uid == settings.selectedInputDeviceUID }) {
            options.append(
                SelectFieldOption(
                    id: settings.selectedInputDeviceUID,
                    displayName: localized("Unavailable device", locale: locale)
                )
            )
        }

        options += availableInputDevices.map {
            SelectFieldOption(
                id: $0.uid,
                displayName: $0.displayName
            )
        }

        return options
    }

    var languageOptions: [SelectFieldOption] {
        AppLanguage.allCases.map {
            SelectFieldOption(
                id: $0.rawValue,
                displayName: $0.pickerLabel(locale: locale),
                isEnabled: $0.isSelectable
            )
        }
    }

    var selectedAudioInputSelection: Binding<String> {
        Binding(
            get: { settings.selectedInputDeviceUID },
            set: { settings.selectedInputDeviceUID = $0 }
        )
    }

    var selectedLanguageSelection: Binding<String> {
        Binding(
            get: { settings.selectedAppLanguage.rawValue },
            set: { settings.selectedAppLanguage = AppLanguage(rawValue: $0) ?? .automatic }
        )
    }
}

enum OutputOption: String, CaseIterable, Identifiable {
    case clipboard = "clipboard"
    case directInsert = "directInsert"
    
    var id: String { rawValue }
 
    func title(locale: Locale) -> String {
        switch self {
        case .clipboard: return localized("Clipboard", locale: locale)
        case .directInsert: return localized("Direct Insert", locale: locale)
        }
    }

    func description(locale: Locale) -> String {
        switch self {
        case .clipboard: return localized("Temporarily copy text, paste it, then restore your clipboard", locale: locale)
        case .directInsert: return localized("Type text directly into the active app when possible", locale: locale)
        }
    }
    
    var icon: Icon {
        switch self {
        case .clipboard: return .clipboard
        case .directInsert: return .textCursor
        }
    }
}

struct OutputOptionRow: View {
    @Environment(\.locale) private var locale
    let option: OutputOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.accent : AppColors.border.opacity(0.9), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 12, height: 12)
                    }
                }
                
                IconView(icon: option.icon, size: 16)
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title(locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(option.description(locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(isSelected ? AppColors.accentBackground : AppColors.mutedSurface.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.accent.opacity(0.6) : AppColors.border.opacity(0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GeneralSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 500)
}
