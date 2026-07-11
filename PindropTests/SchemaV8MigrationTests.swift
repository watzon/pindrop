//
//  SchemaV8MigrationTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized, .enabled(if: sqlite3_libversion_number() > 0, "SQLite is unavailable in this environment"))
struct SchemaV8MigrationTests {
    @Test func migrationFromV7PreservesRecordsAndLeavesNewFieldsNil() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let storeURL = directoryURL.appendingPathComponent("migration-v7-to-v8.store")
        let configuration = ModelConfiguration(url: storeURL)

        try autoreleasepool {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV7.TranscriptionRecord.self,
                TranscriptionRecordSchemaV7.MediaFolder.self,
                TranscriptionRecordSchemaV7.ParticipantProfile.self,
                TranscriptionRecordSchemaV7.ParticipantTrainingEvidence.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                TranscriptionRecordSchemaV7.TranscriptionRecord(
                    text: "Hello schema migration",
                    duration: 3.5,
                    modelUsed: "base",
                    sourceKind: .voiceRecording
                )
            )
            legacyContext.insert(
                TranscriptionRecordSchemaV7.TranscriptionRecord(
                    text: "Second legacy record",
                    duration: 1.0,
                    modelUsed: "tiny",
                    sourceKind: .voiceRecording
                )
            )
            try legacyContext.save()
        }

        let migratedContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            configurations: configuration
        )
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(
            FetchDescriptor<TranscriptionRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )

        #expect(records.count == 2)
        #expect(records.map(\.text).sorted() == ["Hello schema migration", "Second legacy record"].sorted())
        for record in records {
            #expect(record.destinationAppName == nil)
            #expect(record.destinationAppBundleID == nil)
            #expect(record.wordCount == nil)
        }
    }

    @Test func migrationFromV8AddsProfileMetadataDefaults() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let storeURL = directoryURL.appendingPathComponent("migration-v8-to-v9.store")
        let configuration = ModelConfiguration(url: storeURL)

        try autoreleasepool {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV8.TranscriptionRecord.self,
                TranscriptionRecordSchemaV8.MediaFolder.self,
                TranscriptionRecordSchemaV8.ParticipantProfile.self,
                TranscriptionRecordSchemaV8.ParticipantTrainingEvidence.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                TranscriptionRecordSchemaV8.ParticipantProfile(
                    normalizedName: "alice",
                    displayName: "Alice"
                )
            )
            try legacyContext.save()
        }

        let migratedContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            configurations: configuration
        )
        let profiles = try ModelContext(migratedContainer).fetch(FetchDescriptor<ParticipantProfile>())
        let profile = try #require(profiles.first)

        #expect(profiles.count == 1)
        #expect(profile.displayName == "Alice")
        #expect(profile.notes == nil)
        #expect(profile.isCurrentUser == false)
    }
}
