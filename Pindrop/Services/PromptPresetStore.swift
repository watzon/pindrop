//
// PromptPresetStore.swift
// Pindrop
//
// Created on 2026-02-02.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class PromptPresetStore {

    enum PromptPresetStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case cannotDeleteBuiltIn
        case exportFailed(String)
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save preset: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch presets: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete preset: \(message)"
            case .cannotDeleteBuiltIn:
                return "Cannot delete built-in presets"
            case .exportFailed(let message):
                return "Failed to export presets: \(message)"
            case .importFailed(let message):
                return "Failed to import presets: \(message)"
            }
        }
    }

    enum ImportStrategy {
        case additive  // Add new presets, skip existing
        case replace   // Clear custom presets and import
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD Operations

    func fetchAll() throws -> [PromptPreset] {
        let descriptor = FetchDescriptor<PromptPreset>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw PromptPresetStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchBuiltIn() throws -> [PromptPreset] {
        let predicate = #Predicate<PromptPreset> { $0.isBuiltIn == true }
        let descriptor = FetchDescriptor<PromptPreset>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw PromptPresetStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchCustom() throws -> [PromptPreset] {
        let predicate = #Predicate<PromptPreset> { $0.isBuiltIn == false }
        let descriptor = FetchDescriptor<PromptPreset>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw PromptPresetStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func add(_ preset: PromptPreset) throws {
        modelContext.insert(preset)

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.saveFailed(error.localizedDescription)
        }
    }

    func update(_ preset: PromptPreset) throws {
        preset.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.saveFailed(error.localizedDescription)
        }
    }

    func delete(_ preset: PromptPreset) throws {
        guard !preset.isBuiltIn else {
            throw PromptPresetStoreError.cannotDeleteBuiltIn
        }

        modelContext.delete(preset)

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.deleteFailed(error.localizedDescription)
        }
    }

    func duplicate(_ preset: PromptPreset) throws -> PromptPreset {
        let copy = PromptPreset(
            name: "\(preset.name) Copy",
            prompt: preset.prompt,
            isBuiltIn: false,
            sortOrder: preset.sortOrder + 1
        )

        modelContext.insert(copy)

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.saveFailed(error.localizedDescription)
        }

        return copy
    }

    // MARK: - Seeding

    func seedBuiltInPresets() throws {
        let existingBuiltIns = try fetchBuiltIn()
        var builtInsByIdentifier: [String: PromptPreset] = [:]
        var legacyBuiltInsByName: [String: PromptPreset] = [:]

        for preset in existingBuiltIns {
            if let identifier = preset.builtInIdentifier {
                builtInsByIdentifier[identifier] = preset
            } else {
                legacyBuiltInsByName[preset.name.lowercased()] = preset
            }
        }

        for (index, definition) in BuiltInPresets.all.enumerated() {
            if let existingPreset = builtInsByIdentifier[definition.identifier] {
                existingPreset.name = definition.name
                existingPreset.prompt = definition.prompt
                existingPreset.sortOrder = index
                existingPreset.isBuiltIn = true
                existingPreset.updatedAt = Date()
                continue
            }

            if let legacyPreset = legacyBuiltInsByName[definition.name.lowercased()] {
                legacyPreset.builtInIdentifier = definition.identifier
                legacyPreset.name = definition.name
                legacyPreset.prompt = definition.prompt
                legacyPreset.sortOrder = index
                legacyPreset.isBuiltIn = true
                legacyPreset.updatedAt = Date()
                continue
            }

            let preset = PromptPreset(
                name: definition.name,
                prompt: definition.prompt,
                isBuiltIn: true,
                sortOrder: index,
                builtInIdentifier: definition.identifier
            )

            modelContext.insert(preset)
        }

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Import/Export

    func exportToJSON() throws -> Data {
        let presets = try fetchAll()

        struct PresetExport: Codable {
            let name: String
            let prompt: String
            let sortOrder: Int
        }

        struct ExportFormat: Codable {
            let version: Int
            let exportedAt: String
            let presets: [PresetExport]
        }

        let presetExports = presets.map { preset in
            PresetExport(
                name: preset.name,
                prompt: preset.prompt,
                sortOrder: preset.sortOrder
            )
        }

        let exportData = ExportFormat(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            presets: presetExports
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(exportData)
        } catch {
            throw PromptPresetStoreError.exportFailed(error.localizedDescription)
        }
    }

    func importFromJSON(_ data: Data, strategy: ImportStrategy) throws {
        struct PresetImport: Codable {
            let name: String
            let prompt: String
            let sortOrder: Int
        }

        struct ImportFormat: Codable {
            let version: Int
            let exportedAt: String?
            let presets: [PresetImport]
        }

        let importData: ImportFormat
        do {
            importData = try JSONDecoder().decode(ImportFormat.self, from: data)
        } catch {
            throw PromptPresetStoreError.importFailed("Invalid JSON format: \(error.localizedDescription)")
        }

        guard importData.version == 1 else {
            throw PromptPresetStoreError.importFailed("Unsupported version: \(importData.version)")
        }

        if strategy == .replace {
            let existingCustom = try fetchCustom()
            for preset in existingCustom {
                modelContext.delete(preset)
            }
        }

        let existingCustom = try fetchCustom()
        let existingNames = Set(existingCustom.map { $0.name.lowercased() })

        for presetData in importData.presets {
            // Only import custom presets (skip if name matches a built-in)
            let isBuiltInName = BuiltInPresets.all.contains { $0.name.lowercased() == presetData.name.lowercased() }
            guard !isBuiltInName else {
                continue
            }

            if strategy == .additive {
                guard !existingNames.contains(presetData.name.lowercased()) else {
                    continue
                }
            }

            let preset = PromptPreset(
                name: presetData.name,
                prompt: presetData.prompt,
                isBuiltIn: false,
                sortOrder: presetData.sortOrder
            )
            modelContext.insert(preset)
        }

        do {
            try modelContext.save()
        } catch {
            throw PromptPresetStoreError.importFailed("Failed to save imported presets: \(error.localizedDescription)")
        }
    }
}
