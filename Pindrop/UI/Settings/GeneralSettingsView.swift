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
            interfaceLanguageSection
            dictationLanguageSection
            audioInputSection
            floatingIndicatorSection
            dictionarySection
            interfaceSection
            resetSection
        }
    }

    private var interfaceLanguageSection: some View {
        SettingsCard(
            title: localized(L10nKeys.interface, locale: locale),
            icon: "globe",
            detail: localized(
                L10nKeys.chooseLanguagesForTheInterfaceAndForDicta,
                locale: locale
            )
        ) {
            SelectField(
                options: interfaceLanguageOptions,
                selection: selectedAppLocaleSelection,
                placeholder: AppLocale.automatic.displayName(locale: locale)
            )
            .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var dictationLanguageSection: some View {
        SettingsCard(
            title: localized(L10nKeys.language, locale: locale),
            icon: "mic.fill",
            detail: localized(
                L10nKeys.chooseLanguagesForTheInterfaceAndForDicta,
                locale: locale
            )
        ) {
            SelectField(
                options: dictationLanguageOptions,
                selection: selectedAppLanguageSelection,
                placeholder: AppLanguage.automatic.displayName(locale: locale)
            )
            .frame(maxWidth: 320, alignment: .leading)
        }
    }
    
    private var outputSection: some View {
        SettingsCard(
            title: localized(L10nKeys.output, locale: locale),
            icon: "doc.on.clipboard",
            detail: localized(L10nKeys.chooseHowDictatedTextLandsThenTuneTheFin, locale: locale)
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
                    title: localized(L10nKeys.addTrailingSpace, locale: locale),
                    detail: localized(L10nKeys.appendASpaceAfterEachTranscriptionForSeam, locale: locale),
                    isOn: $settings.addTrailingSpace,
                    accessibilityIdentifier: "settings.toggle.addTrailingSpace"
                )

                if AppTestMode.isRunningUITests {
                    Text(settings.addTrailingSpace ? localized(L10nKeys.on, locale: locale) : localized(L10nKeys.off, locale: locale))
                        .font(AppTypography.tiny)
                        .foregroundStyle(AppColors.textTertiary)
                        .accessibilityIdentifier("settings.toggle.addTrailingSpace.state")
                }
            }
        }
    }
    
    private var interfaceSection: some View {
        SettingsCard(
            title: localized(L10nKeys.interface, locale: locale),
            icon: "macwindow",
            detail: localized(L10nKeys.controlHowPindropAppearsInMacosAndWhether, locale: locale)
        ) {
            VStack(spacing: AppTheme.Spacing.lg) {
                SettingsToggleRow(
                    title: localized(L10nKeys.launchAtLogin, locale: locale),
                    detail: localized(L10nKeys.automaticallyStartPindropWhenYouSignIn, locale: locale),
                    isOn: $settings.launchAtLogin,
                    accessibilityIdentifier: "settings.toggle.launchAtLogin"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: localized(L10nKeys.showInDock, locale: locale),
                    detail: localized(L10nKeys.displayPindropInTheDockInsteadOfRunningO, locale: locale),
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
            title: localized(L10nKeys.dictionary, locale: locale),
            icon: "text.book.closed",
            detail: localized(L10nKeys.letPindropQuietlyLearnVocabularyFromTheCo, locale: locale)
        ) {
            SettingsToggleRow(
                title: localized(L10nKeys.learnCorrectedWordsAutomatically, locale: locale),
                detail: localized(L10nKeys.addWordsYouManuallyCorrectIntoYourVocabul, locale: locale),
                isOn: $settings.automaticDictionaryLearningEnabled,
                accessibilityIdentifier: "settings.toggle.automaticDictionaryLearningEnabled"
            )
        }
    }

    private var audioInputSection: some View {
        SettingsCard(
            title: localized(L10nKeys.audioInput, locale: locale),
            icon: "mic",
            detail: localized(L10nKeys.chooseWhichMicrophonePindropShouldUseForD, locale: locale)
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    SelectField(
                        options: audioInputOptions,
                        selection: selectedAudioInputSelection,
                        placeholder: localized(L10nKeys.systemDefault, locale: locale)
                    )
                    .frame(maxWidth: 300, alignment: .leading)

                    Button(localized(L10nKeys.refresh, locale: locale)) {
                        refreshInputDevices()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: localized(L10nKeys.pauseMediaDuringTranscription, locale: locale),
                    detail: localized(L10nKeys.temporarilyPauseActiveMediaPlaybackWhileDi, locale: locale),
                    isOn: $settings.pauseMediaOnRecording,
                    accessibilityIdentifier: "settings.toggle.pauseMediaOnRecording"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: localized(L10nKeys.muteSystemAudioDuringRecording, locale: locale),
                    detail: localized(L10nKeys.temporarilyMuteSpeakerOutputWhileDictation, locale: locale),
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
            title: localized(L10nKeys.reset, locale: locale),
            icon: "arrow.counterclockwise",
            detail: localized(L10nKeys.startFreshWhenYouWantToClearPreferencesO, locale: locale)
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(L10nKeys.resetAllSettings, locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized(L10nKeys.clearsPreferencesAndRestartsOnboarding, locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Text(localized(L10nKeys.reset, locale: locale))
                }
                .buttonStyle(.bordered)
            }
        }
        .alert(localized(L10nKeys.resetAllSettings7262c7b7, locale: locale), isPresented: $showingResetConfirmation) {
            Button(localized(L10nKeys.cancel, locale: locale), role: .cancel) { }
            Button(localized(L10nKeys.reset, locale: locale), role: .destructive) {
                settings.resetAllSettings()
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(localized(L10nKeys.thisWillClearAllYourSettingsIncludingApi, locale: locale))
        }
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.inputDevices()
    }
}

private extension GeneralSettingsView {
    var audioInputOptions: [SelectFieldOption] {
        var options = [SelectFieldOption(id: "", displayName: localized(L10nKeys.systemDefault, locale: locale))]

        if !settings.selectedInputDeviceUID.isEmpty,
           !availableInputDevices.contains(where: { $0.uid == settings.selectedInputDeviceUID }) {
            options.append(
                SelectFieldOption(
                    id: settings.selectedInputDeviceUID,
                    displayName: localized(L10nKeys.unavailableDevice, locale: locale)
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

    var interfaceLanguageOptions: [SelectFieldOption] {
        AppLocale.allCases.map {
            SelectFieldOption(
                id: $0.rawValue,
                displayName: $0.pickerLabel(locale: locale),
                secondaryText: $0.nativeDisplayName(currentLocale: locale),
                isEnabled: $0.isSelectable
            )
        }
    }

    var dictationLanguageOptions: [SelectFieldOption] {
        AppLanguage.allCases.map {
            SelectFieldOption(
                id: $0.rawValue,
                displayName: $0.pickerLabel(locale: locale),
                secondaryText: $0.nativeDisplayName(currentLocale: locale),
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

    var selectedAppLocaleSelection: Binding<String> {
        Binding(
            get: { settings.selectedAppLocale.rawValue },
            set: { settings.selectedAppLocale = AppLocale(rawValue: $0) ?? .automatic }
        )
    }

    var selectedAppLanguageSelection: Binding<String> {
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
        case .clipboard: return localized(L10nKeys.clipboard, locale: locale)
        case .directInsert: return localized(L10nKeys.directInsert, locale: locale)
        }
    }

    func description(locale: Locale) -> String {
        switch self {
        case .clipboard: return localized(L10nKeys.temporarilyCopyTextPasteItThenRestoreYour, locale: locale)
        case .directInsert: return localized(L10nKeys.typeTextDirectlyIntoTheActiveAppWhenPoss, locale: locale)
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
