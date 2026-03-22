//
//  GeneralSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var showingResetConfirmation = false
    @State private var availableInputDevices: [AudioInputDevice] = []
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            outputSection
            audioInputSection
            floatingIndicatorSection
            dictionarySection
            interfaceSection
            resetSection
        }
    }
    
    private var outputSection: some View {
        SettingsCard(
            title: "Output",
            icon: "doc.on.clipboard",
            detail: "Choose how dictated text lands, then tune the final insertion behavior."
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
                    title: "Add trailing space",
                    detail: "Append a space after each transcription for seamless dictation.",
                    isOn: $settings.addTrailingSpace,
                    accessibilityIdentifier: "settings.toggle.addTrailingSpace"
                )

                if AppTestMode.isRunningUITests {
                    Text(settings.addTrailingSpace ? "On" : "Off")
                        .font(AppTypography.tiny)
                        .foregroundStyle(AppColors.textTertiary)
                        .accessibilityIdentifier("settings.toggle.addTrailingSpace.state")
                }
            }
        }
    }
    
    private var interfaceSection: some View {
        SettingsCard(
            title: "Interface",
            icon: "macwindow",
            detail: "Control how Pindrop appears in macOS and whether it starts with your desktop session."
        ) {
            VStack(spacing: AppTheme.Spacing.lg) {
                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Automatically start Pindrop when you sign in.",
                    isOn: $settings.launchAtLogin,
                    accessibilityIdentifier: "settings.toggle.launchAtLogin"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Show in Dock",
                    detail: "Display Pindrop in the Dock instead of running only as a menu bar app.",
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
            title: "Dictionary",
            icon: "text.book.closed",
            detail: "Let Pindrop quietly learn vocabulary from the corrections you make over time."
        ) {
            SettingsToggleRow(
                title: "Learn corrected words automatically",
                detail: "Add words you manually correct into your vocabulary for future transcriptions.",
                isOn: $settings.automaticDictionaryLearningEnabled,
                accessibilityIdentifier: "settings.toggle.automaticDictionaryLearningEnabled"
            )
        }
    }

    private var audioInputSection: some View {
        SettingsCard(
            title: "Audio Input",
            icon: "mic",
            detail: "Choose which microphone Pindrop should use for dictation and how it behaves while recording."
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    SelectField(
                        options: audioInputOptions,
                        selection: selectedAudioInputSelection,
                        placeholder: "System Default"
                    )
                    .frame(maxWidth: 300, alignment: .leading)

                    Button("Refresh") {
                        refreshInputDevices()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "Pause media during transcription",
                    detail: "Temporarily pause active media playback while dictation is recording.",
                    isOn: $settings.pauseMediaOnRecording,
                    accessibilityIdentifier: "settings.toggle.pauseMediaOnRecording"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Mute system audio during recording",
                    detail: "Temporarily mute speaker output while dictation is recording.",
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
            title: "Reset",
            icon: "arrow.counterclockwise",
            detail: "Start fresh when you want to clear preferences, onboarding state, and saved credentials."
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset all settings")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Clears preferences and restarts onboarding")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Text("Reset")
                }
                .buttonStyle(.bordered)
            }
        }
        .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetAllSettings()
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("This will clear all your settings, including API keys, hotkeys, and model preferences. The app will quit and show onboarding again on next launch.")
        }
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.inputDevices()
    }
}

private extension GeneralSettingsView {
    var audioInputOptions: [SelectFieldOption] {
        var options = [SelectFieldOption(id: "", displayName: "System Default")]

        if !settings.selectedInputDeviceUID.isEmpty,
           !availableInputDevices.contains(where: { $0.uid == settings.selectedInputDeviceUID }) {
            options.append(
                SelectFieldOption(
                    id: settings.selectedInputDeviceUID,
                    displayName: "Unavailable device"
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

    var selectedAudioInputSelection: Binding<String> {
        Binding(
            get: { settings.selectedInputDeviceUID },
            set: { settings.selectedInputDeviceUID = $0 }
        )
    }
}

enum OutputOption: String, CaseIterable, Identifiable {
    case clipboard = "clipboard"
    case directInsert = "directInsert"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .directInsert: return "Direct Insert"
        }
    }
    
    var description: String {
        switch self {
        case .clipboard: return "Temporarily copy text, paste it, then restore your clipboard"
        case .directInsert: return "Type text directly into the active app when possible"
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
                    Text(option.title)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(option.description)
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
