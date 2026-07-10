//
//  AIEnhancementAdapterTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct AIEnhancementAdapterTests {

    private func makeCleanStore() -> SettingsStore {
        let store = SettingsStore()
        store.resetAllSettings()
        try? store.deleteAPIEndpoint()
        try? store.deleteAPIKey()
        return store
    }

    // MARK: - Simplified adapter

    @Test func enhanceTranscriptsEnabledMapsToTranscriptionAssignment() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        #expect(!store.enhanceTranscriptsEnabled)

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)

        store.enhanceTranscriptsEnabled = true
        #expect(store.enhanceTranscriptsEnabled)
        #expect(store.assignment(for: .transcriptionEnhancement) != nil)
        #expect(store.enhanceTranscriptsProviderID == openai.id)
        #expect(store.enhanceTranscriptsPresetID == BuiltInPresetID.cleanTranscript)

        store.enhanceTranscriptsEnabled = false
        #expect(!store.enhanceTranscriptsEnabled)
        #expect(store.assignment(for: .transcriptionEnhancement) == nil)
    }

    @Test func enhanceTranscriptsProviderModelPresetRoundTrip() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
        store.enhanceTranscriptsEnabled = true

        store.enhanceTranscriptsModelID = "gpt-4o"
        store.enhanceTranscriptsPresetID = BuiltInPresetID.cleanTranscript

        #expect(store.enhanceTranscriptsModelID == "gpt-4o")
        #expect(store.enhanceTranscriptsPresetID == BuiltInPresetID.cleanTranscript)
        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
    }

    // MARK: - English prompt guarantee

    @Test func setAssignmentDropsUneditedBuiltInEnglishPromptOverride() {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)

        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript,
                promptOverride: BuiltInPresets.cleanTranscript.prompt
            ),
            for: .transcriptionEnhancement
        )

        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
    }

    @Test func setAssignmentDropsLegacyDefaultEnhancementPromptOverride() {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)

        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript,
                promptOverride: SettingsStore.Defaults.aiEnhancementPrompt
            ),
            for: .transcriptionEnhancement
        )

        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
    }

    @Test func setAssignmentPreservesTrueCustomPromptOverride() {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        let custom = "You are a legal writing assistant. Be terse."

        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript,
                promptOverride: custom
            ),
            for: .transcriptionEnhancement
        )

        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == custom)
    }

    @Test func enhanceTranscriptsPromptOverrideRejectsBuiltInEnglishText() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
        store.enhanceTranscriptsEnabled = true
        store.enhanceTranscriptsPresetID = BuiltInPresetID.cleanTranscript

        // Simulate save without editing: UI would write the displayed English default.
        store.enhanceTranscriptsPromptOverride = BuiltInPresets.cleanTranscript.prompt

        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
        #expect(
            store.enhanceTranscriptsResolvedEnglishPrompt()
                == BuiltInPresets.cleanTranscript.prompt
        )
    }

    @Test func resolveAssignmentReturnsEnglishBuiltInPromptWhenNoOverride() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: BuiltInPresetID.cleanTranscript
            ),
            for: .transcriptionEnhancement
        )

        let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
        #expect(resolved?.prompt == BuiltInPresets.cleanTranscript.prompt)
    }

    @Test func builtInPresetsProvideExamplesForUserFacingPresets() {
        let userFacing = [
            BuiltInPresets.cleanTranscript,
            BuiltInPresets.meetingNotes,
            BuiltInPresets.emailDraft,
            BuiltInPresets.socialMedia,
            BuiltInPresets.bulletSummary,
            BuiltInPresets.technical
        ]
        for preset in userFacing {
            #expect(preset.example != nil, "Expected example for \(preset.identifier)")
            #expect(!(preset.example?.input.isEmpty ?? true))
            #expect(!(preset.example?.output.isEmpty ?? true))
        }
    }

    @Test func normalizedPromptOverrideStripsMatchingBuiltIn() {
        let result = BuiltInPresets.normalizedPromptOverride(
            BuiltInPresets.emailDraft.prompt,
            presetID: BuiltInPresets.emailDraft.identifier
        )
        #expect(result == nil)
    }

    @Test func customModeWithClearedOverrideFallsBackToDefaultPreset() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)

        // Custom mode: no preset pointer, true custom override.
        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: nil,
                promptOverride: "You are a custom assistant."
            ),
            for: .transcriptionEnhancement
        )
        #expect(store.assignment(for: .transcriptionEnhancement)?.promptPresetID == nil)
        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride != nil)

        // Simulate the promptOverrideBinding path when the user clears/un-edits back to a
        // built-in English prompt (or empty): override normalizes to nil while still in
        // Custom mode (presetID nil). Must not leave both nil.
        store.setAssignment(
            ModelAssignment(
                providerID: openai.id,
                modelID: "gpt-4o-mini",
                promptPresetID: nil,
                promptOverride: BuiltInPresets.cleanTranscript.prompt
            ),
            for: .transcriptionEnhancement
        )

        let assignment = store.assignment(for: .transcriptionEnhancement)
        #expect(assignment?.promptOverride == nil)
        #expect(assignment?.promptPresetID == BuiltInPresetID.cleanTranscript)

        let resolved = store.resolveAssignment(for: .transcriptionEnhancement)
        #expect(resolved?.prompt == BuiltInPresets.cleanTranscript.prompt)
    }

    @Test func enhanceTranscriptsPromptOverrideEmptyCustomFallsBackToDefaultPreset() throws {
        let store = makeCleanStore()
        defer { store.resetAllSettings() }

        let openai = ProviderConfig(kind: .openai, displayName: "OpenAI")
        store.upsertProvider(openai)
        try store.saveProviderAPIKey("sk-test", forProviderID: openai.id)
        store.enhanceTranscriptsEnabled = true

        store.enhanceTranscriptsPromptOverride = "temporary custom prompt"
        #expect(store.assignment(for: .transcriptionEnhancement)?.promptPresetID == nil)

        store.enhanceTranscriptsPromptOverride = nil
        #expect(store.assignment(for: .transcriptionEnhancement)?.promptOverride == nil)
        #expect(
            store.assignment(for: .transcriptionEnhancement)?.promptPresetID
                == BuiltInPresetID.cleanTranscript
        )
        #expect(
            store.enhanceTranscriptsResolvedEnglishPrompt()
                == BuiltInPresets.cleanTranscript.prompt
        )
    }
}
