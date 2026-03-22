//
// PromptPresetStoreTests.swift
// Pindrop
//
// Created on 2026-02-02.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct PromptPresetStoreTests {
    private func makeStore() throws -> PromptPresetStore {
        let schema = Schema([PromptPreset.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(modelContainer)
        return PromptPresetStore(modelContext: modelContext)
    }

    @Test func addPreset() throws {
        let promptPresetStore = try makeStore()
        let preset = PromptPreset(
            name: "Test Preset",
            prompt: "Test prompt content",
            isBuiltIn: false,
            sortOrder: 0
        )

        try promptPresetStore.add(preset)

        let presets = try promptPresetStore.fetchAll()
        #expect(presets.count == 1)
        #expect(presets.first?.name == "Test Preset")
        #expect(presets.first?.prompt == "Test prompt content")
        #expect(presets.first?.isBuiltIn == false)
    }

    @Test func fetchAllPresets() throws {
        let promptPresetStore = try makeStore()
        let p1 = PromptPreset(name: "Alpha", prompt: "Prompt A", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Beta", prompt: "Prompt B", isBuiltIn: false, sortOrder: 1)
        let p3 = PromptPreset(name: "Gamma", prompt: "Prompt C", isBuiltIn: false, sortOrder: 2)

        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)
        try promptPresetStore.add(p3)

        let presets = try promptPresetStore.fetchAll()
        #expect(presets.count == 3)
        #expect(presets[0].sortOrder == 0)
        #expect(presets[1].sortOrder == 1)
        #expect(presets[2].sortOrder == 2)
    }

    @Test func fetchBuiltInPresets() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        #expect(builtIns.count == BuiltInPresets.all.count)
        #expect(builtIns.allSatisfy { $0.isBuiltIn })
    }

    @Test func fetchCustomPresets() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()

        let custom = PromptPreset(name: "Custom", prompt: "Custom prompt", isBuiltIn: false, sortOrder: 100)
        try promptPresetStore.add(custom)

        let customPresets = try promptPresetStore.fetchCustom()
        #expect(customPresets.count == 1)
        #expect(customPresets.first?.name == "Custom")
        #expect(customPresets.first?.isBuiltIn == false)
    }

    @Test func updatePreset() throws {
        let promptPresetStore = try makeStore()
        let preset = PromptPreset(name: "Original", prompt: "Original prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        var presets = try promptPresetStore.fetchAll()
        let toUpdate = try #require(presets.first)
        toUpdate.name = "Updated"
        toUpdate.prompt = "Updated prompt"

        try promptPresetStore.update(toUpdate)

        presets = try promptPresetStore.fetchAll()
        #expect(presets.count == 1)
        #expect(presets.first?.name == "Updated")
        #expect(presets.first?.prompt == "Updated prompt")
        #expect(presets.first?.updatedAt != nil)
    }

    @Test func deleteCustomPreset() throws {
        let promptPresetStore = try makeStore()
        let preset = PromptPreset(name: "To Delete", prompt: "Delete me", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        var presets = try promptPresetStore.fetchAll()
        #expect(presets.count == 1)

        let toDelete = try #require(presets.first)
        try promptPresetStore.delete(toDelete)

        presets = try promptPresetStore.fetchAll()
        #expect(presets.count == 0)
    }

    @Test func cannotDeleteBuiltInPreset() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        #expect(builtIns.count == BuiltInPresets.all.count)

        let toDelete = try #require(builtIns.first)

        do {
            try promptPresetStore.delete(toDelete)
            Issue.record("Expected cannotDeleteBuiltIn error")
        } catch let storeError as PromptPresetStore.PromptPresetStoreError {
            if case .cannotDeleteBuiltIn = storeError {
                #expect(Bool(true))
            } else {
                Issue.record("Expected cannotDeleteBuiltIn error, got \(storeError)")
            }
        } catch {
            Issue.record("Expected PromptPresetStoreError, got \(error.localizedDescription)")
        }

        let remaining = try promptPresetStore.fetchBuiltIn()
        #expect(remaining.count == BuiltInPresets.all.count)
    }

    @Test func duplicatePreset() throws {
        let promptPresetStore = try makeStore()
        let preset = PromptPreset(name: "Original", prompt: "Original prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        let presets = try promptPresetStore.fetchAll()
        let toDuplicate = try #require(presets.first)

        let copy = try promptPresetStore.duplicate(toDuplicate)

        let allPresets = try promptPresetStore.fetchAll()
        #expect(allPresets.count == 2)
        #expect(copy.name == "Original Copy")
        #expect(copy.prompt == "Original prompt")
        #expect(copy.isBuiltIn == false)
        #expect(copy.sortOrder == 1)
    }

    @Test func seedBuiltInPresets() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()

        let presets = try promptPresetStore.fetchAll()
        #expect(presets.count == BuiltInPresets.all.count)
        #expect(presets.allSatisfy { $0.isBuiltIn })

        let names = Set(presets.map { $0.name })
        for builtIn in BuiltInPresets.all {
            #expect(names.contains(builtIn.name), "Missing built-in preset: \(builtIn.name)")
        }
    }

    @Test func seedBuiltInPresetsIdempotent() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()
        try promptPresetStore.seedBuiltInPresets()

        let presets = try promptPresetStore.fetchAll()
        #expect(presets.count == BuiltInPresets.all.count)
    }

    @Test func seedBuiltInPresetsUpdatesExistingBuiltInByIdentifier() throws {
        let promptPresetStore = try makeStore()
        let stale = PromptPreset(
            name: BuiltInPresets.cleanTranscript.name,
            prompt: "stale prompt",
            isBuiltIn: true,
            sortOrder: 999,
            builtInIdentifier: BuiltInPresets.cleanTranscript.identifier
        )
        try promptPresetStore.add(stale)

        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        let clean = try #require(
            builtIns.first(where: { $0.builtInIdentifier == BuiltInPresets.cleanTranscript.identifier })
        )

        #expect(clean.prompt == BuiltInPresets.cleanTranscript.prompt)
        #expect(clean.sortOrder == 0)
    }

    @Test func seedBuiltInPresetsAdoptsLegacyBuiltInWithoutIdentifier() throws {
        let promptPresetStore = try makeStore()
        let legacy = PromptPreset(
            name: BuiltInPresets.cleanTranscript.name,
            prompt: "legacy stale prompt",
            isBuiltIn: true,
            sortOrder: 500,
            builtInIdentifier: nil
        )
        try promptPresetStore.add(legacy)

        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        let clean = try #require(
            builtIns.first(where: { $0.builtInIdentifier == BuiltInPresets.cleanTranscript.identifier })
        )

        #expect(clean.prompt == BuiltInPresets.cleanTranscript.prompt)
        #expect(clean.sortOrder == 0)
    }

    @Test func cleanTranscriptPresetUsesSingleCommaMapping() {
        let prompt = BuiltInPresets.cleanTranscript.prompt

        #expect(prompt.contains("comma → a single comma (,),"))
        #expect(prompt.contains("comma → ,, question mark") == false)
    }

    @Test func exportToJSON() throws {
        let promptPresetStore = try makeStore()
        let p1 = PromptPreset(name: "Preset One", prompt: "Prompt one", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Preset Two", prompt: "Prompt two", isBuiltIn: false, sortOrder: 1)
        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)

        let jsonData = try promptPresetStore.exportToJSON()

        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        #expect(json != nil)
        #expect(json?["version"] as? Int == 1)
        #expect(json?["exportedAt"] != nil)

        let presets = json?["presets"] as? [[String: Any]]
        #expect(presets?.count == 2)
    }

    @Test func importFromJSONAdditive() throws {
        let promptPresetStore = try makeStore()
        let existing = PromptPreset(name: "Existing", prompt: "Existing prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(existing)

        let importJSON = """
        {
            "version": 1,
            "exportedAt": "2026-02-02T00:00:00Z",
            "presets": [
                {
                    "name": "Existing",
                    "prompt": "Should not be added",
                    "sortOrder": 0
                },
                {
                    "name": "New Preset",
                    "prompt": "New prompt content",
                    "sortOrder": 1
                }
            ]
        }
        """

        let data = try #require(importJSON.data(using: .utf8))
        try promptPresetStore.importFromJSON(data, strategy: .additive)

        let presets = try promptPresetStore.fetchCustom()
        #expect(presets.count == 2)

        let existingPreset = presets.first { $0.name == "Existing" }
        #expect(existingPreset?.prompt == "Existing prompt")

        let newPreset = presets.first { $0.name == "New Preset" }
        #expect(newPreset != nil)
        #expect(newPreset?.prompt == "New prompt content")
    }

    @Test func importFromJSONReplace() throws {
        let promptPresetStore = try makeStore()
        let existing = PromptPreset(name: "Existing", prompt: "Existing prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(existing)

        let importJSON = """
        {
            "version": 1,
            "exportedAt": "2026-02-02T00:00:00Z",
            "presets": [
                {
                    "name": "Replaced Preset",
                    "prompt": "Replaced prompt",
                    "sortOrder": 0
                }
            ]
        }
        """

        let data = try #require(importJSON.data(using: .utf8))
        try promptPresetStore.importFromJSON(data, strategy: .replace)

        let presets = try promptPresetStore.fetchCustom()
        #expect(presets.count == 1)
        #expect(presets.first?.name == "Replaced Preset")
    }

    @Test func exportImportRoundTrip() throws {
        let promptPresetStore = try makeStore()
        let p1 = PromptPreset(name: "Round Trip 1", prompt: "Prompt one", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Round Trip 2", prompt: "Prompt two", isBuiltIn: false, sortOrder: 1)
        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)

        let jsonData = try promptPresetStore.exportToJSON()

        let allPresets = try promptPresetStore.fetchAll()
        for preset in allPresets where !preset.isBuiltIn {
            try promptPresetStore.delete(preset)
        }

        try promptPresetStore.importFromJSON(jsonData, strategy: .additive)

        let imported = try promptPresetStore.fetchCustom()
        #expect(imported.count == 2)

        let names = Set(imported.map { $0.name })
        #expect(names.contains("Round Trip 1"))
        #expect(names.contains("Round Trip 2"))
    }

    @Test func importSkipsBuiltInNames() throws {
        let promptPresetStore = try makeStore()
        try promptPresetStore.seedBuiltInPresets()

        let importJSON = """
        {
            "version": 1,
            "exportedAt": "2026-02-02T00:00:00Z",
            "presets": [
                {
                    "name": "Clean Transcript",
                    "prompt": "Custom prompt",
                    "sortOrder": 0
                }
            ]
        }
        """

        let data = try #require(importJSON.data(using: .utf8))
        try promptPresetStore.importFromJSON(data, strategy: .additive)

        let customPresets = try promptPresetStore.fetchCustom()
        #expect(customPresets.count == 0)
    }
}
