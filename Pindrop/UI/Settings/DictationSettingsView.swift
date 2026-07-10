//
//  DictationSettingsView.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftData
import SwiftUI

struct DictationSettingsView: View {
    @ObservedObject var settings: SettingsStore

    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var availableInputDevices: [AudioInputDevice] = []
    @State private var profiles: [ParticipantProfile] = []
    @State private var diskUsage = DictationAudioDiskUsage(totalBytes: 0, snippetCount: 0)
    @State private var editingProfile: ParticipantProfile?
    @State private var editedName = ""
    @State private var showingDeleteAllAudioConfirmation = false
    @State private var showingManageProfiles = false
    @State private var showingDeleteAllProfilesConfirmation = false
    @State private var errorMessage: String?

    private var identityService: SpeakerIdentityService {
        SpeakerIdentityService(modelContext: modelContext)
    }

    private var retentionService: DictationAudioRetentionService {
        DictationAudioRetentionService(
            historyStore: HistoryStore(modelContext: modelContext),
            settingsStore: settings
        )
    }

    var body: some View {
        SettingsPaneStack {
            // Microphone
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Microphone", locale: locale))
                } control: {
                    HStack(spacing: 8) {
                        Menu {
                            Button(localized("System Default", locale: locale)) {
                                settings.selectedInputDeviceUID = ""
                            }
                            if selectedInputDeviceIsUnavailable {
                                Button(localized("Unavailable device", locale: locale)) {
                                    // Keep current UID
                                }
                            }
                            ForEach(availableInputDevices) { device in
                                Button(device.displayName) {
                                    settings.selectedInputDeviceUID = device.uid
                                }
                            }
                        } label: {
                            SettingsMenuButton(title: selectedMicrophoneLabel)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .accessibilityIdentifier("settings.picker.inputDevice")

                        Button {
                            refreshInputDevices()
                        } label: {
                            SettingsMenuButton(
                                title: localized("Refresh", locale: locale),
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Dictation language
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(
                        title: localized("Dictation Language", locale: locale),
                        subtitle: localized("Separate from the interface language", locale: locale)
                    )
                } control: {
                    Menu {
                        ForEach(AppLanguage.allCases) { language in
                            Button(dictationLanguageLabel(language)) {
                                settings.selectedAppLanguage = language
                            }
                            .disabled(!language.isSelectable)
                        }
                    } label: {
                        SettingsMenuButton(title: dictationLanguageLabel(settings.selectedAppLanguage))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("settings.picker.dictationLanguage")
                }
            }

            // Retention + disk usage
            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Keep dictation audio", locale: locale))
                } control: {
                    Menu {
                        ForEach(DictationRetentionPresentation.pickerOrder) { retention in
                            Button(DictationRetentionPresentation.label(retention, locale: locale)) {
                                settings.dictationAudioRetention = retention
                            }
                        }
                    } label: {
                        SettingsMenuButton(
                            title: DictationRetentionPresentation.label(
                                settings.dictationAudioRetention,
                                locale: locale
                            )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("settings.picker.dictationAudioRetention")
                }

                SettingsRow(showSeparator: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            DictationAudioDiskUsageFormatting.summaryLine(
                                usage: diskUsage,
                                locale: locale
                            )
                        )
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)

                        Button {
                            showingDeleteAllAudioConfirmation = true
                        } label: {
                            Text(localized("Delete all audio…", locale: locale))
                                .font(AppTypography.label)
                                .foregroundStyle(AppColors.error)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.button.deleteAllDictationAudio")
                    }
                } control: {
                    EmptyView()
                }
            }

            // Speaker profiles summary
            SettingsGroupCard {
                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(
                        title: localized("Speaker profiles", locale: locale),
                        subtitle: SpeakerProfileSummaryPresentation.summary(
                            trainedCount: trainedProfileCount,
                            locale: locale
                        )
                    )
                } control: {
                    Button {
                        showingManageProfiles = true
                    } label: {
                        SettingsMenuButton(
                            title: localized("Manage…", locale: locale),
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.button.manageSpeakerProfiles")
                }
            }

            // While recording / output / dictionary (existing settings, restyled)
            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Pause media during transcription", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.pauseMediaOnRecording,
                        label: localized("Pause media during transcription", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.pauseMediaOnRecording")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Mute system audio during recording", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.muteAudioDuringRecording,
                        label: localized("Mute system audio during recording", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.muteAudioDuringRecording")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Output Mode", locale: locale))
                } control: {
                    Menu {
                        Button(localized("Clipboard", locale: locale)) {
                            settings.outputMode = DictationOutputOption.clipboard.rawValue
                        }
                        Button(localized("Direct Insert", locale: locale)) {
                            settings.outputMode = DictationOutputOption.directInsert.rawValue
                        }
                    } label: {
                        SettingsMenuButton(title: outputModeLabel)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("settings.picker.outputMode")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Add trailing space", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.addTrailingSpace,
                        label: localized("Add trailing space", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.addTrailingSpace")
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Learn corrected words automatically", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.automaticDictionaryLearningEnabled,
                        label: localized("Learn corrected words automatically", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.automaticDictionaryLearningEnabled")
                }
            }
        }
        .task {
            refreshInputDevices()
            normalizeRecordingAudioOptions()
            loadProfiles()
            refreshDiskUsage()
        }
        .onChange(of: settings.pauseMediaOnRecording) { _, newValue in
            if newValue { settings.muteAudioDuringRecording = false }
        }
        .onChange(of: settings.muteAudioDuringRecording) { _, newValue in
            if newValue { settings.pauseMediaOnRecording = false }
        }
        .onChange(of: settings.dictationAudioRetention) { _, _ in
            refreshDiskUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            loadProfiles()
            refreshDiskUsage()
        }
        .sheet(isPresented: $showingManageProfiles) {
            // Rename / delete-all / error presentations live on the sheet content:
            // modifiers on the pane don't present while its sheet is up.
            SpeakerProfilesManageSheet(
                profiles: profiles,
                locale: locale,
                onRename: { profile in
                    editedName = profile.displayName
                    editingProfile = profile
                },
                onDelete: { profile in
                    deleteProfile(profile)
                },
                onDeleteAll: {
                    showingDeleteAllProfilesConfirmation = true
                },
                onDone: { showingManageProfiles = false }
            )
            .frame(minWidth: 420, minHeight: 360)
            .alert(
                localized("Rename Participant", locale: locale),
                isPresented: Binding(
                    get: { editingProfile != nil },
                    set: { if !$0 { editingProfile = nil } }
                )
            ) {
                TextField(localized("Name", locale: locale), text: $editedName)
                Button(localized("Cancel", locale: locale), role: .cancel) {
                    editingProfile = nil
                }
                Button(localized("Save", locale: locale)) {
                    saveEditedProfile()
                }
            }
            .confirmationDialog(
                localized("Delete All Participants?", locale: locale),
                isPresented: $showingDeleteAllProfilesConfirmation,
                titleVisibility: .visible
            ) {
                Button(localized("Delete All", locale: locale), role: .destructive) {
                    deleteAllProfiles()
                }
                Button(localized("Cancel", locale: locale), role: .cancel) {}
            } message: {
                Text(localized("This removes all learned voice profiles and training data. This cannot be undone.", locale: locale))
            }
            .alert(
                localized("Error", locale: locale),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(localized("OK", locale: locale), role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
        }
        .alert(
            localized("Error", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil && !showingManageProfiles },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK", locale: locale), role: .cancel) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            localized("Delete all audio?", locale: locale),
            isPresented: $showingDeleteAllAudioConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Delete all audio", locale: locale), role: .destructive) {
                deleteAllAudio()
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(localized("Removes kept dictation audio files. Transcripts stay in your Library.", locale: locale))
        }
    }

    private var trainedProfileCount: Int {
        SpeakerProfileSummaryPresentation.trainedCount(
            evidenceCounts: profiles.map(\.evidenceCount)
        )
    }

    private var selectedMicrophoneLabel: String {
        if settings.selectedInputDeviceUID.isEmpty {
            return localized("System Default", locale: locale)
        }
        if let device = availableInputDevices.first(where: { $0.uid == settings.selectedInputDeviceUID }) {
            return device.displayName
        }
        return localized("Unavailable device", locale: locale)
    }

    private var selectedInputDeviceIsUnavailable: Bool {
        !settings.selectedInputDeviceUID.isEmpty
            && !availableInputDevices.contains { $0.uid == settings.selectedInputDeviceUID }
    }

    private var outputModeLabel: String {
        if settings.outputMode == DictationOutputOption.directInsert.rawValue {
            return localized("Direct Insert", locale: locale)
        }
        return localized("Clipboard", locale: locale)
    }

    private func dictationLanguageLabel(_ language: AppLanguage) -> String {
        let displayName = language.pickerLabel(locale: locale)
        guard let nativeName = language.nativeDisplayName(currentLocale: locale) else {
            return displayName
        }
        return "\(displayName) — \(nativeName)"
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.inputDevices()
    }

    private func normalizeRecordingAudioOptions() {
        if settings.pauseMediaOnRecording && settings.muteAudioDuringRecording {
            settings.muteAudioDuringRecording = false
        }
    }

    private func loadProfiles() {
        do {
            profiles = try identityService.fetchAllProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshDiskUsage() {
        do {
            diskUsage = try retentionService.diskUsage()
        } catch {
            Log.audio.error("Failed to read dictation audio disk usage: \(error.localizedDescription)")
            diskUsage = DictationAudioDiskUsage(totalBytes: 0, snippetCount: 0)
        }
    }

    private func deleteAllAudio() {
        do {
            try retentionService.deleteAllDictationAudio()
            refreshDiskUsage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEditedProfile() {
        guard let profile = editingProfile else { return }
        do {
            try identityService.renameProfile(profile, to: editedName)
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        editingProfile = nil
    }

    private func deleteProfile(_ profile: ParticipantProfile) {
        do {
            try identityService.deleteProfile(profile)
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllProfiles() {
        do {
            try identityService.deleteAllProfiles()
            loadProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Manage profiles sheet

private struct SpeakerProfilesManageSheet: View {
    let profiles: [ParticipantProfile]
    let locale: Locale
    let onRename: (ParticipantProfile) -> Void
    let onDelete: (ParticipantProfile) -> Void
    let onDeleteAll: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localized("Speaker profiles", locale: locale))
                    .font(AppTypography.labelStrongSelected)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(localized("Done", locale: locale), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            if profiles.isEmpty {
                ContentUnavailableView {
                    Label(
                        localized("No learned participants yet", locale: locale),
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } description: {
                    Text(localized("Rename speakers in transcripts to teach Pindrop to recognize voices automatically.", locale: locale))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(AppTypography.labelStrong)
                                Text(
                                    profile.evidenceCount == 0
                                        ? localized("Not enough voice data yet", locale: locale)
                                        : String(
                                            format: localized("%d samples · %@", locale: locale),
                                            profile.evidenceCount,
                                            formattedDuration(profile.totalEvidenceDuration)
                                        )
                                )
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Button {
                                onRename(profile)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help(localized("Rename", locale: locale))
                            .accessibilityLabel(localized("Rename", locale: locale))

                            Button(role: .destructive) {
                                onDelete(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(localized("Delete", locale: locale))
                            .accessibilityLabel(localized("Delete", locale: locale))
                        }
                    }
                }
                .listStyle(.inset)

                if !profiles.isEmpty {
                    Divider()
                    Button(role: .destructive, action: onDeleteAll) {
                        Text(localized("Delete All Participants…", locale: locale))
                    }
                    .padding(12)
                    .accessibilityIdentifier("settings.button.deleteAllParticipants")
                }
            }
        }
        .background(AppColors.windowBackground)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        if seconds < 3600 {
            return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
        }
        return "\(Int(seconds) / 3600)h \((Int(seconds) % 3600) / 60)m"
    }
}

private enum DictationOutputOption: String {
    case clipboard
    case directInsert
}

#Preview {
    DictationSettingsView(settings: SettingsStore())
        .modelContainer(PreviewContainer.empty)
        .frame(width: 620, height: 640)
        .background(AppColors.windowBackground)
        .themeRefresh()
}
