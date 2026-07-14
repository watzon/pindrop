//
//  SchemaV11MigrationTests.swift
//  PindropTests
//
//  Created on 2026-07-14.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct SchemaV11MigrationTests {
    @Test func currentSchemaIsV11WithTrainingContributionTable() throws {
        #expect(TranscriptionRecordSchemaV11.versionIdentifier == .init(1, 0, 10))
        #expect(TranscriptionRecordSchemaV11.models.contains { $0 == TrainingContribution.self })
        #expect(TranscriptionRecordSchemaV11.models.contains { $0 == TranscriptionRecord.self })
    }

    @Test func migrationPlanEndsWithV10ToV11LightweightStage() {
        #expect(TranscriptionRecordMigrationPlan.schemas.count == 11)
        #expect(TranscriptionRecordMigrationPlan.stages.count == 10)
        #expect(TranscriptionRecordMigrationPlan.schemas.last == TranscriptionRecordSchemaV11.self)
    }

    @Test func userEditedAtStartsNilAndTrainingContributionRoundTrips() throws {
        let container = try ModelContainer(
            for: TranscriptionRecord.self, MediaFolder.self, ParticipantProfile.self,
            ParticipantTrainingEvidence.self, TrainingContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let record = TranscriptionRecord(text: "hello world", duration: 1.0, modelUsed: "test")
        context.insert(record)

        let contribution = TrainingContribution(
            kind: .aiEnhancement,
            inputText: "helo world",
            targetText: "hello world",
            modelUsed: "test",
            redactionVersion: TrainingTextRedactor.version
        )
        context.insert(contribution)
        try context.save()

        let fetchedRecords = try context.fetch(FetchDescriptor<TranscriptionRecord>())
        #expect(fetchedRecords.first?.userEditedAt == nil)

        let fetchedContributions = try context.fetch(FetchDescriptor<TrainingContribution>())
        #expect(fetchedContributions.count == 1)
        #expect(fetchedContributions.first?.kind == .aiEnhancement)
        #expect(fetchedContributions.first?.uploadState == .pending)
        #expect(fetchedContributions.first?.redactionVersion == TrainingTextRedactor.version)
    }

    @Test func diskBackedMigrationFromV10AddsContributionTable() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let storeURL = directoryURL.appendingPathComponent("migration.store")

        do {
            let legacySchema = Schema(versionedSchema: TranscriptionRecordSchemaV10.self)
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [ModelConfiguration(schema: legacySchema, url: storeURL)]
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                TranscriptionRecordSchemaV10.TranscriptionRecord(
                    text: "Legacy transcription",
                    duration: 2.0,
                    modelUsed: "base"
                )
            )
            try legacyContext.save()
        }

        let migratedSchema = Schema(versionedSchema: TranscriptionRecordSchemaV11.self)
        let migratedContainer = try ModelContainer(
            for: migratedSchema,
            migrationPlan: TranscriptionRecordMigrationPlan.self,
            configurations: [ModelConfiguration(schema: migratedSchema, url: storeURL)]
        )
        let migratedContext = ModelContext(migratedContainer)

        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")
        #expect(records.first?.userEditedAt == nil)

        // The new table exists and is writable after migration.
        let contributionCount = try migratedContext.fetchCount(FetchDescriptor<TrainingContribution>())
        #expect(contributionCount == 0)
    }
}
