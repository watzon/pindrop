//
//  ContributionServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-14.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
private final class ContributionUploaderSpy: ContributionUploader {
    private(set) var enqueuedIDs: [UUID] = []

    func enqueue(_ contribution: TrainingContribution) {
        enqueuedIDs.append(contribution.id)
    }
}

@MainActor
@Suite(.serialized)
struct ContributionServiceTests {
    private struct Fixture {
        let modelContainer: ModelContainer
        let modelContext: ModelContext
        let settings: SettingsStore
        let uploader: ContributionUploaderSpy
        let service: ContributionService
    }

    private func makeFixture() throws -> Fixture {
        let modelContainer = try ModelContainer(
            for: TrainingContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let settings = SettingsStore()
        settings.resetAllSettings()
        let uploader = ContributionUploaderSpy()
        let service = ContributionService(
            modelContext: modelContext,
            settingsStore: settings,
            uploader: uploader
        )
        return Fixture(
            modelContainer: modelContainer,
            modelContext: modelContext,
            settings: settings,
            uploader: uploader,
            service: service
        )
    }

    private func cleanup(_ fixture: Fixture) {
        fixture.settings.resetAllSettings()
    }

    @Test func recordsNothingWhenOptedOut() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }

        #expect(fixture.settings.trainingDataContributionEnabled == false)
        fixture.service.recordAIEnhancementPair(
            input: "helo world",
            target: "Hello world.",
            modelUsed: "parakeet",
            enhancedWith: "test-model",
            sourceRecordID: UUID()
        )

        #expect(fixture.service.count() == 0)
        #expect(fixture.uploader.enqueuedIDs.isEmpty)
    }

    @Test func recordsAIEnhancementPairWhenOptedIn() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        let recordID = UUID()
        fixture.service.recordAIEnhancementPair(
            input: "helo world",
            target: "Hello world.",
            modelUsed: "parakeet",
            enhancedWith: "test-model",
            sourceRecordID: recordID
        )

        let stored = try fixture.service.fetchAll()
        #expect(stored.count == 1)
        #expect(stored.first?.kind == .aiEnhancement)
        #expect(stored.first?.inputText == "helo world")
        #expect(stored.first?.targetText == "Hello world.")
        #expect(stored.first?.modelUsed == "parakeet")
        #expect(stored.first?.enhancedWith == "test-model")
        #expect(stored.first?.sourceRecordID == recordID)
        #expect(stored.first?.uploadState == .pending)
        #expect(fixture.uploader.enqueuedIDs.count == 1)
    }

    @Test func recordsManualEditPairWhenOptedIn() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        fixture.service.recordManualEdit(
            input: "the quick brwn fox",
            target: "the quick brown fox",
            modelUsed: "parakeet",
            sourceRecordID: UUID()
        )

        let stored = try fixture.service.fetchAll()
        #expect(stored.count == 1)
        #expect(stored.first?.kind == .manualEdit)
        #expect(stored.first?.enhancedWith == nil)
    }

    @Test func skipsIdentityPairs() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        fixture.service.recordManualEdit(
            input: "same text",
            target: "  same text  ",
            modelUsed: nil,
            sourceRecordID: nil
        )

        #expect(fixture.service.count() == 0)
    }

    @Test func redactsStoredTexts() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        fixture.service.recordManualEdit(
            input: "email jane@example.com about it",
            target: "Email jane@example.com about it today.",
            modelUsed: nil,
            sourceRecordID: nil
        )

        let stored = try fixture.service.fetchAll()
        #expect(stored.first?.inputText == "email <email> about it")
        #expect(stored.first?.targetText == "Email <email> about it today.")
        #expect(stored.first?.redactionVersion == TrainingTextRedactor.version)
    }

    @Test func deleteAllRemovesEverything() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        fixture.service.recordManualEdit(input: "a b", target: "A b.", modelUsed: nil, sourceRecordID: nil)
        fixture.service.recordManualEdit(input: "c d", target: "C d.", modelUsed: nil, sourceRecordID: nil)
        #expect(fixture.service.count() == 2)

        try fixture.service.deleteAll()
        #expect(fixture.service.count() == 0)
    }

    @Test func jsonlExportMatchesResearchSchemaAndOmitsSourceRecordID() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        fixture.settings.trainingDataContributionEnabled = true

        fixture.service.recordAIEnhancementPair(
            input: "helo",
            target: "Hello.",
            modelUsed: "parakeet",
            enhancedWith: "test-model",
            sourceRecordID: UUID()
        )

        let data = ContributionService.jsonlData(from: try fixture.service.fetchAll())
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        )
        #expect(object["input_text"] as? String == "helo")
        #expect(object["target_text"] as? String == "Hello.")
        #expect(object["primary_transformation_type"] as? String == "ai_enhancement")
        #expect(object["synthetic_or_observed"] as? String == "observed")
        #expect(object["recognizer"] as? String == "parakeet")
        #expect(object["enhanced_with"] as? String == "test-model")
        #expect(object["source"] as? String == "pindrop-first-party")
        #expect(object["example_id"] != nil)
        #expect(object["created_at"] != nil)
        #expect(object["source_record_id"] == nil)
        #expect(object["sourceRecordID"] == nil)
    }

    @Test func historyStoreSaveCapturesEnhancementPair() throws {
        let modelContainer = try ModelContainer(
            for: TranscriptionRecord.self, MediaFolder.self, ParticipantProfile.self,
            ParticipantTrainingEvidence.self, TrainingContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let settings = SettingsStore()
        settings.resetAllSettings()
        defer { settings.resetAllSettings() }
        settings.trainingDataContributionEnabled = true

        let service = ContributionService(modelContext: modelContext, settingsStore: settings)
        let historyStore = HistoryStore(modelContext: modelContext, contributionService: service)

        let record = try historyStore.save(
            text: "Hello world.",
            originalText: "helo world",
            duration: 1.2,
            modelUsed: "parakeet",
            enhancedWith: "test-model"
        )

        let stored = try service.fetchAll()
        #expect(stored.count == 1)
        #expect(stored.first?.sourceRecordID == record.id)

        // Unenhanced saves produce no pair.
        try historyStore.save(
            text: "Plain dictation.",
            duration: 0.8,
            modelUsed: "parakeet"
        )
        #expect(service.count() == 1)
    }
}
