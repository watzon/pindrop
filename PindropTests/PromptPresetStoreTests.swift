//
// PromptPresetStoreTests.swift
// Pindrop
//
// Created on 2026-02-02.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class PromptPresetStoreTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var promptPresetStore: PromptPresetStore!

    override func setUp() async throws {
        let schema = Schema([PromptPreset.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        promptPresetStore = PromptPresetStore(modelContext: modelContext)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        promptPresetStore = nil
    }

    // MARK: - CRUD Tests

    func testAddPreset() throws {
        let preset = PromptPreset(
            name: "Test Preset",
            prompt: "Test prompt content",
            isBuiltIn: false,
            sortOrder: 0
        )

        try promptPresetStore.add(preset)

        let presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets.first?.name, "Test Preset")
        XCTAssertEqual(presets.first?.prompt, "Test prompt content")
        XCTAssertFalse(presets.first?.isBuiltIn ?? true)
    }

    func testFetchAllPresets() throws {
        let p1 = PromptPreset(name: "Alpha", prompt: "Prompt A", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Beta", prompt: "Prompt B", isBuiltIn: false, sortOrder: 1)
        let p3 = PromptPreset(name: "Gamma", prompt: "Prompt C", isBuiltIn: false, sortOrder: 2)

        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)
        try promptPresetStore.add(p3)

        let presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets[0].sortOrder, 0)
        XCTAssertEqual(presets[1].sortOrder, 1)
        XCTAssertEqual(presets[2].sortOrder, 2)
    }

    func testFetchBuiltInPresets() throws {
        // Seed built-in presets first
        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        XCTAssertEqual(builtIns.count, BuiltInPresets.all.count)
        XCTAssertTrue(builtIns.allSatisfy { $0.isBuiltIn })
    }

    func testFetchCustomPresets() throws {
        // Seed built-in presets
        try promptPresetStore.seedBuiltInPresets()

        // Add custom preset
        let custom = PromptPreset(name: "Custom", prompt: "Custom prompt", isBuiltIn: false, sortOrder: 100)
        try promptPresetStore.add(custom)

        let customPresets = try promptPresetStore.fetchCustom()
        XCTAssertEqual(customPresets.count, 1)
        XCTAssertEqual(customPresets.first?.name, "Custom")
        XCTAssertFalse(customPresets.first?.isBuiltIn ?? true)
    }

    func testUpdatePreset() throws {
        let preset = PromptPreset(name: "Original", prompt: "Original prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        // Fetch and update
        var presets = try promptPresetStore.fetchAll()
        let toUpdate = presets.first!
        toUpdate.name = "Updated"
        toUpdate.prompt = "Updated prompt"

        try promptPresetStore.update(toUpdate)

        // Verify update
        presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets.first?.name, "Updated")
        XCTAssertEqual(presets.first?.prompt, "Updated prompt")
        XCTAssertNotNil(presets.first?.updatedAt)
    }

    func testDeleteCustomPreset() throws {
        let preset = PromptPreset(name: "To Delete", prompt: "Delete me", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        var presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, 1)

        let toDelete = presets.first!
        try promptPresetStore.delete(toDelete)

        presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, 0)
    }

    func testCannotDeleteBuiltInPreset() throws {
        // Seed built-in presets
        try promptPresetStore.seedBuiltInPresets()

        let builtIns = try promptPresetStore.fetchBuiltIn()
        XCTAssertEqual(builtIns.count, BuiltInPresets.all.count)

        let toDelete = builtIns.first!

        XCTAssertThrowsError(try promptPresetStore.delete(toDelete)) { error in
            guard let storeError = error as? PromptPresetStore.PromptPresetStoreError else {
                XCTFail("Expected PromptPresetStoreError")
                return
            }
            if case .cannotDeleteBuiltIn = storeError {
            } else {
                XCTFail("Expected cannotDeleteBuiltIn error, got \(storeError)")
            }
        }

        // Verify preset still exists
        let remaining = try promptPresetStore.fetchBuiltIn()
        XCTAssertEqual(remaining.count, BuiltInPresets.all.count)
    }

    func testDuplicatePreset() throws {
        let preset = PromptPreset(name: "Original", prompt: "Original prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(preset)

        let presets = try promptPresetStore.fetchAll()
        let toDuplicate = presets.first!

        let copy = try promptPresetStore.duplicate(toDuplicate)

        let allPresets = try promptPresetStore.fetchAll()
        XCTAssertEqual(allPresets.count, 2)

        // Verify copy properties
        XCTAssertEqual(copy.name, "Original Copy")
        XCTAssertEqual(copy.prompt, "Original prompt")
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertEqual(copy.sortOrder, 1)
    }

    // MARK: - Seeding Tests

    func testSeedBuiltInPresets() throws {
        try promptPresetStore.seedBuiltInPresets()

        let presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, BuiltInPresets.all.count)

        // Verify all are built-in
        XCTAssertTrue(presets.allSatisfy { $0.isBuiltIn })

        // Verify all built-in presets exist by name
        let names = Set(presets.map { $0.name })
        for builtIn in BuiltInPresets.all {
            XCTAssertTrue(names.contains(builtIn.name), "Missing built-in preset: \(builtIn.name)")
        }
    }

    func testSeedBuiltInPresetsIdempotent() throws {
        // Seed twice
        try promptPresetStore.seedBuiltInPresets()
        try promptPresetStore.seedBuiltInPresets()

        let presets = try promptPresetStore.fetchAll()
        XCTAssertEqual(presets.count, BuiltInPresets.all.count)
    }

    // MARK: - Import/Export Tests

    func testExportToJSON() throws {
        // Add some presets
        let p1 = PromptPreset(name: "Preset One", prompt: "Prompt one", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Preset Two", prompt: "Prompt two", isBuiltIn: false, sortOrder: 1)
        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)

        let jsonData = try promptPresetStore.exportToJSON()

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertNotNil(json?["exportedAt"])

        let presets = json?["presets"] as? [[String: Any]]
        XCTAssertEqual(presets?.count, 2)
    }

    func testImportFromJSONAdditive() throws {
        // Add existing preset
        let existing = PromptPreset(name: "Existing", prompt: "Existing prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(existing)

        // Create import JSON
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

        let data = importJSON.data(using: .utf8)!
        try promptPresetStore.importFromJSON(data, strategy: .additive)

        let presets = try promptPresetStore.fetchCustom()
        XCTAssertEqual(presets.count, 2)

        // Verify existing was not overwritten
        let existingPreset = presets.first { $0.name == "Existing" }
        XCTAssertEqual(existingPreset?.prompt, "Existing prompt")

        // Verify new was added
        let newPreset = presets.first { $0.name == "New Preset" }
        XCTAssertNotNil(newPreset)
        XCTAssertEqual(newPreset?.prompt, "New prompt content")
    }

    func testImportFromJSONReplace() throws {
        // Add existing preset
        let existing = PromptPreset(name: "Existing", prompt: "Existing prompt", isBuiltIn: false, sortOrder: 0)
        try promptPresetStore.add(existing)

        // Create import JSON
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

        let data = importJSON.data(using: .utf8)!
        try promptPresetStore.importFromJSON(data, strategy: .replace)

        let presets = try promptPresetStore.fetchCustom()
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets.first?.name, "Replaced Preset")
    }

    func testExportImportRoundTrip() throws {
        // Add presets
        let p1 = PromptPreset(name: "Round Trip 1", prompt: "Prompt one", isBuiltIn: false, sortOrder: 0)
        let p2 = PromptPreset(name: "Round Trip 2", prompt: "Prompt two", isBuiltIn: false, sortOrder: 1)
        try promptPresetStore.add(p1)
        try promptPresetStore.add(p2)

        // Export
        let jsonData = try promptPresetStore.exportToJSON()

        // Clear all presets
        let allPresets = try promptPresetStore.fetchAll()
        for preset in allPresets {
            if !preset.isBuiltIn {
                try promptPresetStore.delete(preset)
            }
        }

        // Import
        try promptPresetStore.importFromJSON(jsonData, strategy: .additive)

        // Verify
        let imported = try promptPresetStore.fetchCustom()
        XCTAssertEqual(imported.count, 2)

        let names = Set(imported.map { $0.name })
        XCTAssertTrue(names.contains("Round Trip 1"))
        XCTAssertTrue(names.contains("Round Trip 2"))
    }

    func testImportSkipsBuiltInNames() throws {
        // Seed built-ins first
        try promptPresetStore.seedBuiltInPresets()

        // Try to import a preset with a built-in name
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

        let data = importJSON.data(using: .utf8)!
        try promptPresetStore.importFromJSON(data, strategy: .additive)

        // Should not add the built-in name
        let customPresets = try promptPresetStore.fetchCustom()
        XCTAssertEqual(customPresets.count, 0)
    }
}
