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
    @State private var editingProfile: ParticipantProfile?
    @State private var editedName = ""
    @State private var showingDeleteAllConfirmation = false
    @State private var errorMessage: String?

    private var identityService: SpeakerIdentityService {
        SpeakerIdentityService(modelContext: modelContext)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(localized("Input Device", locale: locale)) {
                    HStack {
                        Picker("", selection: $settings.selectedInputDeviceUID) {
                            Text(localized("System Default", locale: locale))
                                .tag("")

                            if selectedInputDeviceIsUnavailable {
                                Text(localized("Unavailable device", locale: locale))
                                    .tag(settings.selectedInputDeviceUID)
                            }

                            ForEach(availableInputDevices) { device in
                                Text(device.displayName)
                                    .tag(device.uid)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.picker.inputDevice")

                        Button(localized("Refresh", locale: locale)) {
                            refreshInputDevices()
                        }
                    }
                }
            } header: {
                Text(localized("Microphone", locale: locale))
            } footer: {
                Text(localized("Choose which microphone Pindrop uses for dictation.", locale: locale))
            }

            Section {
                Picker(
                    localized("Dictation Language", locale: locale),
                    selection: dictationLanguageBinding
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(dictationLanguageLabel(language))
                            .tag(language)
                            .disabled(!language.isSelectable)
                    }
                }
                .accessibilityIdentifier("settings.picker.dictationLanguage")
            } header: {
                Text(localized("Language", locale: locale))
            } footer: {
                Text(localized("Select the language Pindrop should expect when transcribing speech.", locale: locale))
            }

            Section {
                Toggle(
                    localized("Pause media during transcription", locale: locale),
                    isOn: $settings.pauseMediaOnRecording
                )
                .accessibilityIdentifier("settings.toggle.pauseMediaOnRecording")

                Toggle(
                    localized("Mute system audio during recording", locale: locale),
                    isOn: $settings.muteAudioDuringRecording
                )
                .accessibilityIdentifier("settings.toggle.muteAudioDuringRecording")
            } header: {
                Text(localized("While Recording", locale: locale))
            } footer: {
                Text(localized("These options are mutually exclusive. Enabling one turns the other off.", locale: locale))
            }

            Section {
                Picker(localized("Output Mode", locale: locale), selection: $settings.outputMode) {
                    Text(localized("Clipboard", locale: locale))
                        .tag(DictationOutputOption.clipboard.rawValue)
                    Text(localized("Direct Insert", locale: locale))
                        .tag(DictationOutputOption.directInsert.rawValue)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.picker.outputMode")

                Toggle(
                    localized("Add trailing space", locale: locale),
                    isOn: $settings.addTrailingSpace
                )
                .accessibilityIdentifier("settings.toggle.addTrailingSpace")

                if AppTestMode.isRunningUITests {
                    Text(settings.addTrailingSpace ? localized("On", locale: locale) : localized("Off", locale: locale))
                        .accessibilityIdentifier("settings.toggle.addTrailingSpace.state")
                }
            } header: {
                Text(localized("Output", locale: locale))
            } footer: {
                Text(localized("Clipboard temporarily copies the transcript for pasting. Direct Insert types into the active app when possible.", locale: locale))
            }

            Section {
                Toggle(
                    localized("Learn corrected words automatically", locale: locale),
                    isOn: $settings.automaticDictionaryLearningEnabled
                )
                .accessibilityIdentifier("settings.toggle.automaticDictionaryLearningEnabled")
            } header: {
                Text(localized("Dictionary", locale: locale))
            } footer: {
                Text(localized("Words you manually correct can be added to your vocabulary for future dictation.", locale: locale))
            }

            Section(localized("Speakers", locale: locale)) {
                if profiles.isEmpty {
                    ContentUnavailableView {
                        Label(
                            localized("No learned participants yet", locale: locale),
                            systemImage: "person.crop.circle.badge.questionmark"
                        )
                    } description: {
                        Text(localized("Rename speakers in transcripts to teach Pindrop to recognize voices automatically.", locale: locale))
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                } else {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                }
            }

            if !profiles.isEmpty {
                Section {
                    Button(localized("Delete All Participants…", locale: locale), role: .destructive) {
                        showingDeleteAllConfirmation = true
                    }
                    .accessibilityIdentifier("settings.button.deleteAllParticipants")
                } footer: {
                    Text(localized("This removes all learned voice profiles and training data. This cannot be undone.", locale: locale))
                }
            }
        }
        .formStyle(.grouped)
        .task {
            refreshInputDevices()
            normalizeRecordingAudioOptions()
            loadProfiles()
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
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            loadProfiles()
        }
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
        .confirmationDialog(
            localized("Delete All Participants?", locale: locale),
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Delete All", locale: locale), role: .destructive) {
                deleteAllProfiles()
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(localized("This removes all learned voice profiles and training data. This cannot be undone.", locale: locale))
        }
    }

    private var dictationLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { settings.selectedAppLanguage },
            set: { settings.selectedAppLanguage = $0 }
        )
    }

    private var selectedInputDeviceIsUnavailable: Bool {
        !settings.selectedInputDeviceUID.isEmpty
            && !availableInputDevices.contains { $0.uid == settings.selectedInputDeviceUID }
    }

    private func dictationLanguageLabel(_ language: AppLanguage) -> String {
        let displayName = language.pickerLabel(locale: locale)
        guard let nativeName = language.nativeDisplayName(currentLocale: locale) else {
            return displayName
        }
        return "\(displayName) — \(nativeName)"
    }

    private func profileRow(_ profile: ParticipantProfile) -> some View {
        LabeledContent {
            HStack {
                Button {
                    editedName = profile.displayName
                    editingProfile = profile
                } label: {
                    Image(systemName: "pencil")
                }
                .help(localized("Rename", locale: locale))

                Button(role: .destructive) {
                    deleteProfile(profile)
                } label: {
                    Image(systemName: "trash")
                }
                .help(localized("Delete", locale: locale))
            }
        } label: {
            VStack(alignment: .leading) {
                Text(profile.displayName)
                if profile.evidenceCount == 0 {
                    Text(localized("Not enough voice data yet", locale: locale))
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        String(
                            format: localized("%d samples · %@", locale: locale),
                            profile.evidenceCount,
                            formattedDuration(profile.totalEvidenceDuration)
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
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
}
