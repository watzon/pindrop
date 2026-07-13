//
//  StatusBarControllerTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import AppKit
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct StatusBarControllerTests {
    @Test func promptPresetMenuShowsSelectionAndRoutesChanges() throws {
        let settingsStore = SettingsStore()
        settingsStore.resetAllSettings()
        defer { settingsStore.resetAllSettings() }

        let provider = ProviderConfig(kind: .openai, displayName: "OpenAI")
        settingsStore.upsertProvider(provider)
        settingsStore.setAssignment(
            ModelAssignment(
                providerID: provider.id,
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript
            ),
            for: .transcriptionEnhancement
        )

        let audioRecorder = try AudioRecorder(
            permissionManager: MockPermissionProvider(),
            captureBackend: MockAudioCaptureBackend(identifier: "microphone"),
            systemAudioCaptureBackend: MockAudioCaptureBackend(identifier: "system")
        )
        let sut = StatusBarController(
            audioRecorder: audioRecorder,
            settingsStore: settingsStore
        )
        let clean = StatusBarController.PromptPresetOption(
            id: "clean-row-id",
            assignmentID: BuiltInPresetID.cleanTranscript,
            name: "Clean Transcript"
        )
        let meeting = StatusBarController.PromptPresetOption(
            id: "meeting-row-id",
            assignmentID: BuiltInPresets.meetingNotes.identifier,
            name: "Meeting Notes"
        )

        sut.updatePromptPresets([clean, meeting])

        var menu = try #require(sut.promptPresetMenuForTesting())
        #expect(menu.items.count == 2)
        #expect(menu.items[0].title == clean.name)
        #expect(menu.items[0].state == .on)
        #expect(menu.items[1].title == meeting.name)
        #expect(menu.items[1].state == .off)
        #expect(sut.promptPresetMenuItemForTesting()?.isEnabled == true)

        var didApplySelection = false
        sut.onSelectPromptPreset = { option in
            didApplySelection = AppCoordinator.applyPromptPresetSelection(
                option,
                to: settingsStore
            )
        }
        menu.performActionForItem(at: 1)
        #expect(didApplySelection)
        #expect(
            settingsStore.assignment(for: .transcriptionEnhancement)?.promptPresetID
                == meeting.assignmentID
        )
        #expect(settingsStore.selectedPresetId == meeting.id)

        #expect(menu.items[0].state == .off)
        #expect(menu.items[1].state == .on)

        settingsStore.selectedAppLocale = .german
        sut.reloadLocalizedStrings()
        menu = try #require(sut.promptPresetMenuForTesting())
        #expect(menu.items.count == 2)
        #expect(menu.items[0].state == .off)
        #expect(menu.items[1].state == .on)
        #expect(
            sut.promptPresetMenuItemForTesting()?.title
                == localized("Prompt Preset", locale: AppLocale.german.locale)
        )

        settingsStore.setAssignment(nil, for: .transcriptionEnhancement)
        sut.updateDynamicItems()
        #expect(sut.promptPresetMenuItemForTesting()?.isEnabled == false)
        #expect(!menu.items[0].isEnabled)
        #expect(!menu.items[1].isEnabled)

        sut.updatePromptPresets([])
        #expect(menu.items.isEmpty)
    }

    @Test func promptPresetSelectionMapsCustomIDsAndNoOpsWhenDisabled() {
        let settingsStore = SettingsStore()
        settingsStore.resetAllSettings()
        defer { settingsStore.resetAllSettings() }

        let customID = UUID().uuidString
        let custom = StatusBarController.PromptPresetOption(
            id: customID,
            assignmentID: customID,
            name: "Custom Preset"
        )

        #expect(!AppCoordinator.applyPromptPresetSelection(custom, to: settingsStore))
        #expect(settingsStore.selectedPresetId == nil)

        settingsStore.setAssignment(
            ModelAssignment(
                providerID: UUID(),
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript
            ),
            for: .transcriptionEnhancement
        )

        #expect(AppCoordinator.applyPromptPresetSelection(custom, to: settingsStore))
        #expect(
            settingsStore.assignment(for: .transcriptionEnhancement)?.promptPresetID
                == customID
        )
        #expect(settingsStore.selectedPresetId == customID)
    }
}
