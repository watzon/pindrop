//
//  HistoryStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized, .enabled(if: sqlite3_libversion_number() > 0, "SQLite is unavailable in this environment"))
struct HistoryStoreTests {
    private struct Fixture {
        let modelContainer: ModelContainer
        let modelContext: ModelContext
        let historyStore: HistoryStore
        let speakerIdentityService: SpeakerIdentityService
    }

    private func makeFixture() throws -> Fixture {
        let modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(modelContainer)
        let speakerIdentityService = SpeakerIdentityService(modelContext: modelContext)
        let historyStore = HistoryStore(modelContext: modelContext, speakerIdentityService: speakerIdentityService)
        return Fixture(
            modelContainer: modelContainer,
            modelContext: modelContext,
            historyStore: historyStore,
            speakerIdentityService: speakerIdentityService
        )
    }

    private func requireSQLiteSupport() throws {
    }

    @Test func diskBackedMigrationFromV3PreservesExistingTranscriptions() throws {
        try requireSQLiteSupport()
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent("migration.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV3.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            let legacyRecord = TranscriptionRecordSchemaV3.TranscriptionRecord(
                text: "Legacy transcription",
                originalText: nil,
                duration: 4.2,
                modelUsed: "base",
                enhancedWith: nil,
                diarizationSegmentsJSON: nil
            )
            legacyContext.insert(legacyRecord)
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
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")
        #expect(records.first?.resolvedSourceKind == .voiceRecording)
        #expect(records.first?.managedMediaPath == nil)

        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func diskBackedMigrationFromV4LeavesExistingTranscriptionsUnfiled() throws {
        try requireSQLiteSupport()
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent("migration-v4.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV4.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                TranscriptionRecordSchemaV4.TranscriptionRecord(
                    text: "Folderless legacy transcription",
                    duration: 7.5,
                    modelUsed: "base",
                    sourceKind: .webLink,
                    sourceDisplayName: "Migration Fixture",
                    originalSourceURL: "https://example.com/video",
                    managedMediaPath: "/tmp/migration-fixture.mp4"
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
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Folderless legacy transcription")
        #expect(records.first?.folder == nil)

        try? FileManager.default.removeItem(at: directoryURL)
    }
    
    @Test func saveTranscription() throws {
        let fixture = try makeFixture()

        try fixture.historyStore.save(
            text: "Hello, world!",
            duration: 5.0,
            modelUsed: "tiny"
        )
        
        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.text == "Hello, world!")
        #expect(records.first?.duration == 5.0)
        #expect(records.first?.modelUsed == "tiny")
    }

    @Test func saveAndFetchPreservesDiarizationSegmentsJSON() throws {
        let fixture = try makeFixture()
        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","startTime":0,"endTime":1.4,"confidence":0.9,"text":"hello"}]
        """

        try fixture.historyStore.save(
            text: "Speaker 1: hello",
            duration: 1.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON
        )

        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.diarizationSegmentsJSON == diarizationJSON)
    }

    @Test func saveWithoutDiarizationMetadataDefaultsToNil() throws {
        let fixture = try makeFixture()

        try fixture.historyStore.save(
            text: "No diarization metadata",
            duration: 2.0,
            modelUsed: "base"
        )

        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.diarizationSegmentsJSON == nil)
    }

    @Test func updateSpeakerLabelsUpdatesPersistedDiarizedSegments() throws {
        let fixture = try makeFixture()
        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","startTime":0,"endTime":1.0,"confidence":0.9,"text":"hello"},{"speakerId":"speaker-b","speakerLabel":"Speaker 2","startTime":1.0,"endTime":2.0,"confidence":0.8,"text":"hi"}]
        """

        let record = try fixture.historyStore.save(
            text: "Speaker 1: hello\nSpeaker 2: hi",
            duration: 2.0,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON
        )

        try fixture.historyStore.updateSpeakerLabels(
            record: record,
            labelsBySpeakerID: [
                "speaker-a": "Alice",
                "speaker-b": "Bob"
            ]
        )

        let fetchedRecord = try #require(try fixture.historyStore.fetchRecord(with: record.id))
        #expect(fetchedRecord.diarizedSegments.map(\.speakerLabel) == ["Alice", "Bob"])
    }

    @Test func updateSpeakerLabelsLearnsParticipantProfilesFromRenames() throws {
        let fixture = try makeFixture()

        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","speakerEmbedding":[0.1,0.2,0.3],"startTime":0,"endTime":1.4,"confidence":0.9,"text":"hello"}]
        """

        let record = try fixture.historyStore.save(
            text: "Speaker 1: hello",
            duration: 1.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON
        )

        try fixture.historyStore.updateSpeakerLabels(
            record: record,
            labelsBySpeakerID: ["speaker-a": "Alice"]
        )

        let profiles = try fixture.modelContext.fetch(FetchDescriptor<ParticipantProfile>())
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())

        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Alice")
        #expect(profiles.first?.evidenceCount == 1)
        #expect(profiles.first?.totalEvidenceDuration == 1.4)
        #expect(evidence.count == 1)
        #expect(evidence.first?.profile?.displayName == "Alice")
        #expect(evidence.first?.recordID == record.id)
    }

    @Test func updateSpeakerLabelsCreatesParticipantProfileWithoutEligibleEvidence() throws {
        let fixture = try makeFixture()

        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","startTime":0,"endTime":0.4,"confidence":0.9,"text":"hi"}]
        """

        let record = try fixture.historyStore.save(
            text: "Speaker 1: hi",
            duration: 0.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON
        )

        try fixture.historyStore.updateSpeakerLabels(
            record: record,
            labelsBySpeakerID: ["speaker-a": "Alice"]
        )

        let profiles = try fixture.modelContext.fetch(FetchDescriptor<ParticipantProfile>())
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())

        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Alice")
        #expect(profiles.first?.evidenceCount == 0)
        #expect(profiles.first?.totalEvidenceDuration == 0)
        #expect(evidence.isEmpty)
    }

    @Test func speakerIdentityBestMatchReturnsProfileWhenSimilarityAndMarginPass() throws {
        let fixture = try makeFixture()
        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(alice)

        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        bob.centroidEmbeddingData = try JSONEncoder().encode([0.0 as Float, 1.0, 0.0])
        fixture.modelContext.insert(bob)
        try fixture.modelContext.save()

        let match = try fixture.speakerIdentityService.bestMatch(for: [0.98, 0.02, 0.0])

        #expect(match?.displayName == "Alice")
        #expect((match?.similarity ?? 0) > 0.72)
    }

    @Test func speakerIdentityBestMatchReturnsNilWhenMarginIsTooSmall() throws {
        let fixture = try makeFixture()
        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0])
        fixture.modelContext.insert(alice)

        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        bob.centroidEmbeddingData = try JSONEncoder().encode([0.99 as Float, 0.01])
        fixture.modelContext.insert(bob)
        try fixture.modelContext.save()

        let match = try fixture.speakerIdentityService.bestMatch(for: [1.0, 0.0])

        #expect(match == nil)
    }

    // MARK: - Profile Management Tests

    @Test func fetchAllProfilesReturnsProfilesSortedByName() throws {
        let fixture = try makeFixture()
        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        fixture.modelContext.insert(bob)
        fixture.modelContext.insert(alice)
        try fixture.modelContext.save()

        let profiles = try fixture.speakerIdentityService.fetchAllProfiles()

        #expect(profiles.count == 2)
        #expect(profiles[0].displayName == "Alice")
        #expect(profiles[1].displayName == "Bob")
    }

    @Test func renameProfileUpdatesDisplayNameAndNormalizedName() throws {
        let fixture = try makeFixture()
        let profile = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        fixture.modelContext.insert(profile)
        try fixture.modelContext.save()

        try fixture.speakerIdentityService.renameProfile(profile, to: "Alicia")

        let fetched = try fixture.speakerIdentityService.fetchAllProfiles()
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Alicia")
        #expect(fetched[0].normalizedName == "alicia")
    }

    @Test func deleteProfileRemovesProfileAndEvidence() throws {
        let fixture = try makeFixture()
        let profile = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        profile.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(profile)
        try fixture.modelContext.save()

        let evidence = ParticipantTrainingEvidence(
            evidenceKey: "test-key",
            sourceTypeRawValue: "renameFeedback",
            recordID: UUID(),
            sourceSpeakerID: "speaker-a",
            segmentStartTime: 0.0,
            segmentEndTime: 1.5,
            segmentDuration: 1.5,
            confidence: 0.9,
            embeddingData: try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        )
        evidence.profile = profile
        fixture.modelContext.insert(evidence)
        try fixture.modelContext.save()

        try fixture.speakerIdentityService.deleteProfile(profile)

        let profiles = try fixture.speakerIdentityService.fetchAllProfiles()
        #expect(profiles.isEmpty)

        let allEvidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
        #expect(allEvidence.isEmpty)
    }

    @Test func deleteAllProfilesRemovesEverything() throws {
        let fixture = try makeFixture()
        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        fixture.modelContext.insert(alice)
        fixture.modelContext.insert(bob)
        try fixture.modelContext.save()

        try fixture.speakerIdentityService.deleteAllProfiles()

        let profiles = try fixture.speakerIdentityService.fetchAllProfiles()
        #expect(profiles.isEmpty)
    }

    @Test func saveMediaTranscriptionPersistsMediaMetadata() throws {
        let fixture = try makeFixture()

        let record = try fixture.historyStore.save(
            text: "Transcript",
            duration: 12.5,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Example Video",
            originalSourceURL: "https://example.com/watch?v=123",
            managedMediaPath: "/tmp/example-video.mp4",
            thumbnailPath: "/tmp/example-video.png"
        )

        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.id == record.id)
        #expect(records.first?.resolvedSourceKind == .webLink)
        #expect(records.first?.sourceDisplayName == "Example Video")
        #expect(records.first?.originalSourceURL == "https://example.com/watch?v=123")
        #expect(records.first?.managedMediaPath == "/tmp/example-video.mp4")
        #expect(records.first?.thumbnailPath == "/tmp/example-video.png")
        #expect(records.first?.isMediaTranscription == true)
    }

    @Test func saveMediaTranscriptionPersistsSelectedFolder() throws {
        let fixture = try makeFixture()
        let folder = try fixture.historyStore.createFolder(named: "Interviews")
        let record = try fixture.historyStore.save(
            text: "Transcript",
            duration: 12.5,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Example Video",
            originalSourceURL: "https://example.com/watch?v=123",
            managedMediaPath: "/tmp/example-video.mp4",
            folderID: folder.id
        )

        #expect(record.folder?.id == folder.id)
        let fetchedRecords = try fixture.historyStore.fetchAll()
        #expect(fetchedRecords.first?.folder?.name == "Interviews")
    }
    
    @Test func fetchTranscriptions() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        try fixture.historyStore.save(text: "Third", duration: 3.0, modelUsed: "small")
        
        let allRecords = try fixture.historyStore.fetchAll()
        #expect(allRecords.count == 3)
        #expect(allRecords[0].text == "Third")
        #expect(allRecords[1].text == "Second")
        #expect(allRecords[2].text == "First")
        
        let limitedRecords = try fixture.historyStore.fetch(limit: 2)
        #expect(limitedRecords.count == 2)
        #expect(limitedRecords[0].text == "Third")
        #expect(limitedRecords[1].text == "Second")
    }

    @Test func fetchVoiceTranscriptionsSupportsOffsetPagination() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "First voice", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Second voice", duration: 2.0, modelUsed: "base")
        try fixture.historyStore.save(
            text: "Media item",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .webLink,
            sourceDisplayName: "Example media",
            managedMediaPath: "/tmp/example.mp4"
        )
        try fixture.historyStore.save(text: "Third voice", duration: 4.0, modelUsed: "large")

        let firstPage = try fixture.historyStore.fetchVoiceTranscriptions(limit: 2)
        let secondPage = try fixture.historyStore.fetchVoiceTranscriptions(limit: 2, offset: 2)

        #expect(firstPage.map(\.text) == ["Third voice", "Second voice"])
        #expect(secondPage.map(\.text) == ["First voice"])
        #expect((firstPage + secondPage).allSatisfy { $0.isVoiceTranscription })
    }

    @Test func countVoiceTranscriptionsRespectsSearchQuery() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "Alpha voice", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Beta voice", duration: 2.0, modelUsed: "base")
        try fixture.historyStore.save(
            text: "Alpha media",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "alpha.mov",
            managedMediaPath: "/tmp/alpha.mov"
        )

        #expect(try fixture.historyStore.countVoiceTranscriptions() == 2)
        #expect(try fixture.historyStore.countVoiceTranscriptions(query: "Alpha") == 1)
        #expect(try fixture.historyStore.countVoiceTranscriptions(query: "Beta") == 1)
        #expect(try fixture.historyStore.countVoiceTranscriptions(query: "media") == 0)
    }
    
    @Test func searchTranscriptions() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "The quick brown fox", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "jumps over the lazy dog", duration: 2.0, modelUsed: "base")
        try fixture.historyStore.save(text: "Hello world", duration: 3.0, modelUsed: "small")
        
        let results = try fixture.historyStore.search(query: "quick")
        #expect(results.count == 1)
        #expect(results.first?.text == "The quick brown fox")
        
        let multipleResults = try fixture.historyStore.search(query: "the")
        #expect(multipleResults.count == 2)
        
        let noResults = try fixture.historyStore.search(query: "nonexistent")
        #expect(noResults.count == 0)
    }

    @Test func fetchMediaRecordsOnlyReturnsMediaBackedTranscriptions() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "Voice", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(
            text: "Linked media",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Linked media",
            originalSourceURL: "https://example.com/video",
            managedMediaPath: "/tmp/linked.mp4"
        )
        try fixture.historyStore.save(
            text: "Imported file",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "clip.mov",
            managedMediaPath: "/tmp/clip.mov"
        )

        let records = try fixture.historyStore.fetchMediaRecords()
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.isMediaTranscription })
        #expect(records.map(\.resolvedSourceKind) == [.importedFile, .webLink])
    }

    @Test func voiceAndMediaClassificationMatchesSourceKind() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "Voice", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(
            text: "Linked media",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Linked media",
            originalSourceURL: "https://example.com/video",
            managedMediaPath: "/tmp/linked.mp4"
        )
        try fixture.historyStore.save(
            text: "Imported file",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "clip.mov",
            managedMediaPath: "/tmp/clip.mov"
        )

        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 3)

        let recordsByText = Dictionary(uniqueKeysWithValues: records.map { ($0.text, $0) })
        #expect(recordsByText["Voice"]?.isVoiceTranscription == true)
        #expect(recordsByText["Voice"]?.isMediaTranscription == false)
        #expect(recordsByText["Linked media"]?.isVoiceTranscription == false)
        #expect(recordsByText["Linked media"]?.isMediaTranscription == true)
        #expect(recordsByText["Imported file"]?.isVoiceTranscription == false)
        #expect(recordsByText["Imported file"]?.isMediaTranscription == true)
    }
    
    @Test func deleteTranscription() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "To be deleted", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "To be kept", duration: 2.0, modelUsed: "base")
        
        var records = try fixture.historyStore.fetchAll()
        #expect(records.count == 2)
        
        let recordToDelete = try #require(records.first { $0.text == "To be deleted" })
        try fixture.historyStore.delete(recordToDelete)
        
        records = try fixture.historyStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.text == "To be kept")
    }
    
    @Test func deleteAll() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        try fixture.historyStore.save(text: "Third", duration: 3.0, modelUsed: "small")
        
        var records = try fixture.historyStore.fetchAll()
        #expect(records.count == 3)
        
        try fixture.historyStore.deleteAll()
        
        records = try fixture.historyStore.fetchAll()
        #expect(records.count == 0)
    }

    @Test func deleteRemovesManagedMediaAssets() throws {
        let fixture = try makeFixture()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let mediaURL = tempDirectory.appendingPathComponent("media.mp4")
        let thumbnailURL = tempDirectory.appendingPathComponent("thumbnail.png")
        try Data("media".utf8).write(to: mediaURL)
        try Data("thumb".utf8).write(to: thumbnailURL)

        let record = try fixture.historyStore.save(
            text: "Media",
            duration: 8.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "media.mp4",
            managedMediaPath: mediaURL.path,
            thumbnailPath: thumbnailURL.path
        )

        #expect(FileManager.default.fileExists(atPath: mediaURL.path))
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try fixture.historyStore.delete(record)

        #expect(FileManager.default.fileExists(atPath: mediaURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: tempDirectory.path) == false)
    }
    
    @Test func timestampOrdering() async throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        try fixture.historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        
        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 2)
        #expect(records[0].text == "Second")
        #expect(records[1].text == "First")
        #expect(records[0].timestamp > records[1].timestamp)
    }
    
    @Test func uniqueIDs() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        
        let records = try fixture.historyStore.fetchAll()
        #expect(records.count == 2)
        #expect(records[0].id != records[1].id)
    }
    
    @Test func caseInsensitiveSearch() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "Hello World", duration: 1.0, modelUsed: "tiny")
        
        let lowerResults = try fixture.historyStore.search(query: "hello")
        #expect(lowerResults.count == 1)
        
        let upperResults = try fixture.historyStore.search(query: "WORLD")
        #expect(upperResults.count == 1)
        
        let mixedResults = try fixture.historyStore.search(query: "HeLLo WoRLd")
        #expect(mixedResults.count == 1)
    }

    @Test func createRenameAndFetchFolders() throws {
        let fixture = try makeFixture()
        let folder = try fixture.historyStore.createFolder(named: " Interviews ")
        #expect(folder.name == "Interviews")

        try fixture.historyStore.renameFolder(folder, to: "Customer Interviews")

        let folders = try fixture.historyStore.fetchFolders()
        #expect(folders.map(\.name) == ["Customer Interviews"])
    }

    @Test func createFolderRejectsDuplicateNamesCaseInsensitively() throws {
        let fixture = try makeFixture()
        _ = try fixture.historyStore.createFolder(named: "Interviews")

        do {
            _ = try fixture.historyStore.createFolder(named: "interviews")
            Issue.record("Expected duplicate-name HistoryStoreError")
        } catch let historyError as HistoryStore.HistoryStoreError {
            if case .saveFailed(let message) = historyError {
                #expect(message.contains("already exists"))
            } else {
                Issue.record("Expected saveFailed duplicate-name error, got \(historyError)")
            }
        } catch {
            Issue.record("Expected HistoryStoreError, got \(error)")
        }
    }

    @Test func deleteFolderUnassignsTranscriptionsInsteadOfDeletingThem() throws {
        let fixture = try makeFixture()
        let folder = try fixture.historyStore.createFolder(named: "Interviews")
        let record = try fixture.historyStore.save(
            text: "Transcript",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Interview",
            managedMediaPath: "/tmp/interview.mp4",
            folderID: folder.id
        )

        try fixture.historyStore.deleteFolder(folder)

        let folders = try fixture.historyStore.fetchFolders()
        let records = try fixture.historyStore.fetchAll()

        #expect(folders.isEmpty)
        #expect(records.count == 1)
        #expect(records.first?.id == record.id)
        #expect(records.first?.folder == nil)
    }

    @Test func assignAndRemoveTranscriptionFolder() throws {
        let fixture = try makeFixture()
        let folder = try fixture.historyStore.createFolder(named: "Research")
        let record = try fixture.historyStore.save(
            text: "Transcript",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Research Call",
            managedMediaPath: "/tmp/research.mp4"
        )

        try fixture.historyStore.assign(record: record, to: folder)
        #expect(record.folder?.id == folder.id)

        try fixture.historyStore.removeFromFolder(record: record)
        #expect(record.folder == nil)
    }

    @Test func fetchMediaLibrarySearchesTranscriptAndMetadata() throws {
        let fixture = try makeFixture()
        let folder = try fixture.historyStore.createFolder(named: "Research")
        try fixture.historyStore.save(
            text: "The product team discussed roadmap risks.",
            originalText: "roadmap risks",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Quarterly Research",
            originalSourceURL: "https://example.com/research",
            managedMediaPath: "/tmp/research.mp4",
            folderID: folder.id
        )
        try fixture.historyStore.save(
            text: "Another transcript",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "Design Review",
            managedMediaPath: "/tmp/design.mov"
        )

        #expect(try fixture.historyStore.fetchMediaLibrary(query: "roadmap").count == 1)
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Quarterly").count == 1)
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "example.com/research").count == 1)
        #expect(try fixture.historyStore.fetchMediaLibrary(folderID: folder.id, query: "roadmap").count == 1)
        #expect(try fixture.historyStore.fetchMediaLibrary(folderID: folder.id, query: "Design").isEmpty)
    }

    @Test func fetchMediaLibrarySortsByNameAndDate() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(
            text: "Zulu",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Zulu Call",
            managedMediaPath: "/tmp/zulu.mp4"
        )
        try fixture.historyStore.save(
            text: "Alpha",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Alpha Call",
            managedMediaPath: "/tmp/alpha.mp4"
        )

        let newest = try fixture.historyStore.fetchMediaLibrary(sort: .newest)
        let oldest = try fixture.historyStore.fetchMediaLibrary(sort: .oldest)
        let ascending = try fixture.historyStore.fetchMediaLibrary(sort: .nameAscending)
        let descending = try fixture.historyStore.fetchMediaLibrary(sort: .nameDescending)

        #expect(newest.first?.sourceDisplayName == "Alpha Call")
        #expect(oldest.first?.sourceDisplayName == "Zulu Call")
        #expect(ascending.map(\.sourceDisplayName) == ["Alpha Call", "Zulu Call"])
        #expect(descending.map(\.sourceDisplayName) == ["Zulu Call", "Alpha Call"])
    }
    
    // MARK: - Export Tests
    
    @Test func exportToJSON() throws {
        let fixture = try makeFixture()

        try fixture.historyStore.save(text: "First transcription", duration: 5.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Second transcription", duration: 10.0, modelUsed: "base")
        
        let records = try fixture.historyStore.fetchAll()
        
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_export.json")
        
        try? FileManager.default.removeItem(at: testURL)
        
        _ = try exportToJSONInternal(records: records, to: testURL)
        
        #expect(FileManager.default.fileExists(atPath: testURL.path))
        
        let jsonData = try Data(contentsOf: testURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
        }
        
        let exportData = try decoder.decode(ExportData.self, from: jsonData)
        
        #expect(exportData.totalRecords == 2)
        #expect(exportData.records.count == 2)
        #expect(exportData.records[0].text == "Second transcription")
        #expect(exportData.records[0].duration == 10.0)
        #expect(exportData.records[0].modelUsed == "base")
        #expect(exportData.records[1].text == "First transcription")
        #expect(exportData.records[1].duration == 5.0)
        #expect(exportData.records[1].modelUsed == "tiny")
        
        try? FileManager.default.removeItem(at: testURL)
    }
    
    @Test func exportToCSV() throws {
        let fixture = try makeFixture()

        try fixture.historyStore.save(text: "First transcription", duration: 5.0, modelUsed: "tiny")
        try fixture.historyStore.save(text: "Text with \"quotes\" and, commas", duration: 10.0, modelUsed: "base")
        
        let records = try fixture.historyStore.fetchAll()
        
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_export.csv")
        
        try? FileManager.default.removeItem(at: testURL)
        
        try exportToCSVInternal(records: records, to: testURL)
        
        #expect(FileManager.default.fileExists(atPath: testURL.path))
        
        let csvContent = try String(contentsOf: testURL, encoding: .utf8)
        let lines = csvContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        #expect(lines.count == 3)
        #expect(lines[0].starts(with: "ID,Timestamp,Duration,Model,Text"))
        #expect(lines[1].contains("\"Text with \"\"quotes\"\" and, commas\""))
        #expect(lines[1].contains("10.00"))
        #expect(lines[1].contains("base"))
        #expect(lines[2].contains("\"First transcription\""))
        #expect(lines[2].contains("5.00"))
        #expect(lines[2].contains("tiny"))
        
        try? FileManager.default.removeItem(at: testURL)
    }
    
    @Test func exportEmptyRecords() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_empty.json")
        
        do {
            try exportToJSONInternal(records: [], to: testURL)
            Issue.record("Expected exportFailed HistoryStoreError")
        } catch let historyError as HistoryStore.HistoryStoreError {
            if case .exportFailed(let message) = historyError {
                #expect(message == "No records to export")
            } else {
                Issue.record("Expected exportFailed error, got \(historyError)")
            }
        } catch {
            Issue.record("Expected HistoryStoreError, got \(error)")
        }
    }

    @Test func repairServiceRepairsStoreWithV3TablesAndV1Metadata() throws {
        try requireSQLiteSupport()
        let brokenStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("broken.store")
        let referenceStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("reference-v1.store")
        let repairService = SwiftDataStoreRepairService()

        try createV3Store(at: brokenStoreURL)
        try createV1Store(at: referenceStoreURL)
        try overwriteMetadataAndModelCache(at: brokenStoreURL, using: referenceStoreURL)

        do {
            _ = try makeCurrentContainer(at: brokenStoreURL)
            Issue.record("Expected legacy container creation to fail before repair")
        } catch {
            #expect(Bool(true))
        }

        let repairOutcome = try repairService.repairIfNeeded(storeURL: brokenStoreURL)
        #expect(repairOutcome.repaired)
        #expect(repairOutcome.backupDirectoryURL != nil)

        let repairedContainer = try makeCurrentContainer(at: brokenStoreURL)
        let repairedContext = ModelContext(repairedContainer)
        let records = try repairedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")
        #expect(records.first?.resolvedSourceKind == .voiceRecording)

        try? FileManager.default.removeItem(at: brokenStoreURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: referenceStoreURL.deletingLastPathComponent())
    }

    @Test func repairServiceRecreatesMissingPromptPresetTableWhenMetadataVersionMatches() throws {
        try requireSQLiteSupport()
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("missing-prompt-preset.store")
        let repairService = SwiftDataStoreRepairService()

        let seedContainer = try makeCurrentContainer(at: storeURL)
        let seedContext = ModelContext(seedContainer)
        seedContext.insert(
            TranscriptionRecord(
                text: "Existing transcription",
                duration: 2.5,
                modelUsed: "base"
            )
        )
        try seedContext.save()

        try withDatabase(at: storeURL) { database in
            try execute("DROP TABLE ZPROMPTPRESET", on: database)
        }

        #expect(try tableExists(named: "ZPROMPTPRESET", at: storeURL) == false)

        let repairOutcome = try repairService.repairIfNeeded(storeURL: storeURL)
        #expect(repairOutcome.repaired)
        #expect(repairOutcome.backupDirectoryURL != nil)
        #expect(try tableExists(named: "ZPROMPTPRESET", at: storeURL))

        let repairedContainer = try makeCurrentContainer(at: storeURL)
        let repairedContext = ModelContext(repairedContainer)
        let records = try repairedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Existing transcription")

        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func prepareStoreLocationMigratesRecognizedLegacyStore() throws {
        try requireSQLiteSupport()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createV3Store(at: legacyStoreURL)

        try repairService.prepareStoreLocation()

        let migratedStoreURL = repairService.storeURL()
        #expect(FileManager.default.fileExists(atPath: migratedStoreURL.path))

        let migratedContainer = try makeCurrentContainer(at: migratedStoreURL)
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    @Test func prepareStoreLocationMigratesV4LegacyStoreToCurrentSchema() throws {
        try requireSQLiteSupport()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createV4Store(at: legacyStoreURL)

        try repairService.prepareStoreLocation()

        let migratedStoreURL = repairService.storeURL()
        #expect(FileManager.default.fileExists(atPath: migratedStoreURL.path))

        let migratedContainer = try makeCurrentContainer(at: migratedStoreURL)
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")
        #expect(records.first?.folder == nil)

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    @Test func currentContainerMigratesLegacyStoreWithoutPromptPresetModel() throws {
        try requireSQLiteSupport()
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("legacy-no-prompt-preset.store")

        try createV4StoreWithoutPromptPreset(at: storeURL)

        do {
            _ = try makeCurrentContainer(at: storeURL)
        } catch {
            Issue.record("Expected current container migration to succeed, got \(error)")
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func prepareStoreLocationIgnoresUnrecognizedLegacyStore() throws {
        try requireSQLiteSupport()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createUnrecognizedStore(at: legacyStoreURL)

        try repairService.prepareStoreLocation()

        #expect(FileManager.default.fileExists(atPath: repairService.storeURL().path) == false)
        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    @Test func prepareStoreLocationAllowsFreshStoreCreationWhenLegacyStoreIsUnrecognized() throws {
        try requireSQLiteSupport()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createUnrecognizedStore(at: legacyStoreURL)
        try repairService.prepareStoreLocation()

        let currentStoreURL = repairService.storeURL()
        let container = try makeCurrentContainer(at: currentStoreURL)
        let context = ModelContext(container)
        context.insert(
            TranscriptionRecord(
                text: "Fresh transcription",
                duration: 1.0,
                modelUsed: "base"
            )
        )
        try context.save()

        let records = try context.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(currentStoreURL.path.contains("/Pindrop/default.store"))
        #expect(FileManager.default.fileExists(atPath: currentStoreURL.path))
        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
        #expect(records.count == 1)
        #expect(records.first?.text == "Fresh transcription")

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    @Test func prepareStoreLocationRestoresLegacyStoreWhenCurrentStoreIsUnrecognized() throws {
        try requireSQLiteSupport()
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createV4Store(at: legacyStoreURL)
        try createUnrecognizedStore(at: repairService.storeURL())

        try repairService.prepareStoreLocation()

        let restoredContainer = try makeCurrentContainer(at: repairService.storeURL())
        let restoredContext = ModelContext(restoredContainer)
        let records = try restoredContext.fetch(FetchDescriptor<TranscriptionRecord>())

        #expect(records.count == 1)
        #expect(records.first?.text == "Legacy transcription")

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    // MARK: - Test Helpers
    
    private func exportToJSONInternal(records: [TranscriptionRecord], to url: URL) throws {
        guard !records.isEmpty else {
            throw HistoryStore.HistoryStoreError.exportFailed("No records to export")
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
        }
        
        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        let exportRecords = records.map { record in
            ExportRecord(
                id: record.id.uuidString,
                text: record.text,
                timestamp: dateFormatter.string(from: record.timestamp),
                duration: record.duration,
                modelUsed: record.modelUsed
            )
        }
        
        let exportData = ExportData(
            exportDate: dateFormatter.string(from: Date()),
            totalRecords: records.count,
            records: exportRecords
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: url)
        } catch {
            throw HistoryStore.HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    private func exportToCSVInternal(records: [TranscriptionRecord], to url: URL) throws {
        guard !records.isEmpty else {
            throw HistoryStore.HistoryStoreError.exportFailed("No records to export")
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        var csvContent = "ID,Timestamp,Duration,Model,Text\n"
        
        for record in records {
            let escapedText = record.text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            
            let row = [
                record.id.uuidString,
                dateFormatter.string(from: record.timestamp),
                String(format: "%.2f", record.duration),
                record.modelUsed,
                "\"\(escapedText)\""
            ].joined(separator: ",")
            
            csvContent += row + "\n"
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStore.HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }

    private func createV1Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try autoreleasepool {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: TranscriptionRecordSchemaV1.TranscriptionRecordV1.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )

            let context = ModelContext(container)
            context.insert(
                TranscriptionRecordSchemaV1.TranscriptionRecordV1(
                    text: "Original transcription",
                    duration: 2.0,
                    modelUsed: "tiny"
                )
            )
            try context.save()
        }
        try flushSQLiteStore(at: storeURL)
    }

    private func createV3Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try autoreleasepool {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: TranscriptionRecordSchemaV3.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )

            let context = ModelContext(container)
            context.insert(
                TranscriptionRecordSchemaV3.TranscriptionRecord(
                    text: "Legacy transcription",
                    originalText: "Legacy transcription",
                    duration: 4.2,
                    modelUsed: "base",
                    enhancedWith: nil,
                    diarizationSegmentsJSON: nil
                )
            )
            try context.save()
        }
        try flushSQLiteStore(at: storeURL)
    }

    private func createV4Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try autoreleasepool {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: TranscriptionRecordSchemaV4.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )

            let context = ModelContext(container)
            context.insert(
                TranscriptionRecordSchemaV4.TranscriptionRecord(
                    text: "Legacy transcription",
                    originalText: "Legacy transcription",
                    duration: 4.2,
                    modelUsed: "base",
                    enhancedWith: nil,
                    diarizationSegmentsJSON: nil,
                    sourceKind: .voiceRecording,
                    sourceDisplayName: nil,
                    originalSourceURL: nil,
                    managedMediaPath: nil,
                    thumbnailPath: nil
                )
            )
            try context.save()
        }
        try flushSQLiteStore(at: storeURL)
    }

    private func createV4StoreWithoutPromptPreset(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try autoreleasepool {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: TranscriptionRecordSchemaV4.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                configurations: configuration
            )

            let context = ModelContext(container)
            context.insert(
                TranscriptionRecordSchemaV4.TranscriptionRecord(
                    text: "Legacy transcription",
                    originalText: "Legacy transcription",
                    duration: 4.2,
                    modelUsed: "base",
                    enhancedWith: nil,
                    diarizationSegmentsJSON: nil,
                    sourceKind: .voiceRecording,
                    sourceDisplayName: nil,
                    originalSourceURL: nil,
                    managedMediaPath: nil,
                    thumbnailPath: nil
                )
            )
            try context.save()
        }
        try flushSQLiteStore(at: storeURL)
    }

    private func createUnrecognizedStore(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_close(database)
            throw NSError(domain: "HistoryStoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }

        defer { sqlite3_close(database) }

        guard let database else {
            throw NSError(domain: "HistoryStoreTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create SQLite database"])
        }

        let sql = "CREATE TABLE IF NOT EXISTS unrelated_table (id INTEGER PRIMARY KEY)"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }
    }

    private func makeCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(
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
    }

    private func overwriteMetadataAndModelCache(at targetStoreURL: URL, using referenceStoreURL: URL) throws {
        let referenceMetadata = try fetchBlob(
            sql: "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
            at: referenceStoreURL
        )
        let referenceModelCache = try fetchBlob(
            sql: "SELECT Z_CONTENT FROM Z_MODELCACHE LIMIT 1",
            at: referenceStoreURL
        )

        try withDatabase(at: targetStoreURL) { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try updateBlob(
                    sql: "UPDATE Z_METADATA SET Z_PLIST = ? WHERE Z_VERSION = 1",
                    blob: referenceMetadata,
                    on: database
                )
                try execute("DELETE FROM Z_MODELCACHE", on: database)
                try updateBlob(
                    sql: "INSERT INTO Z_MODELCACHE (Z_CONTENT) VALUES (?)",
                    blob: referenceModelCache,
                    on: database
                )
                try execute("COMMIT TRANSACTION", on: database)
            } catch {
                try? execute("ROLLBACK TRANSACTION", on: database)
                throw error
            }
        }
    }

    private func fetchBlob(sql: String, at storeURL: URL) throws -> Data {
        try withDatabase(at: storeURL) { database in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw sqliteError(on: database)
            }

            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw sqliteError(on: database)
            }

            guard let bytes = sqlite3_column_blob(statement, 0) else {
                return Data()
            }

            let count = Int(sqlite3_column_bytes(statement, 0))
            return Data(bytes: bytes, count: count)
        }
    }

    private func updateBlob(sql: String, blob: Data, on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }

        defer { sqlite3_finalize(statement) }

        let bindResult = blob.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(
                statement,
                1,
                rawBuffer.baseAddress,
                Int32(blob.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
        guard bindResult == SQLITE_OK else {
            throw sqliteError(on: database)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(on: database)
        }
    }

    private func tableExists(named table: String, at storeURL: URL) throws -> Bool {
        try withDatabase(at: storeURL) { database in
            var statement: OpaquePointer?
            let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw sqliteError(on: database)
            }

            defer { sqlite3_finalize(statement) }

            guard sqlite3_bind_text(
                statement,
                1,
                (table as NSString).utf8String,
                -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            ) == SQLITE_OK else {
                throw sqliteError(on: database)
            }

            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }
    }

    private func withDatabase<T>(at url: URL, _ work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let error = sqliteError(on: database)
            sqlite3_close(database)
            throw error
        }

        defer { sqlite3_close(database) }

        guard let database else {
            throw sqliteError(on: nil)
        }

        sqlite3_busy_timeout(database, 5_000)

        return try work(database)
    }

    private func flushSQLiteStore(at storeURL: URL) throws {
        var lastError: Error?

        for _ in 0..<5 {
            do {
                try withDatabase(at: storeURL) { database in
                    try execute("PRAGMA wal_checkpoint(TRUNCATE)", on: database)
                }
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private func sqliteError(on database: OpaquePointer?) -> NSError {
        let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "HistoryStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
