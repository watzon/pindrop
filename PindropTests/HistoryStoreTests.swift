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
    private enum SpeakerLearningTestError: Error {
        case failed
    }

    private final class FailingSpeakerIdentityService: SpeakerIdentityManaging {
        func bestMatch(for embedding: [Float]) throws -> SpeakerIdentityMatch? { nil }
        func learnFromDictation(recordID: UUID, segments: [DiarizedTranscriptSegment]) throws {
            throw SpeakerLearningTestError.failed
        }
        func learnFromProfileAssignments(
            recordID: UUID,
            segments: [DiarizedTranscriptSegment],
            profileIDsBySpeakerID: [String: UUID]
        ) throws {}
        func hasTrainingEvidence(for recordID: UUID) throws -> Bool { false }
        func removeTrainingEvidence(for recordID: UUID) throws {}
        func removeTrainingEvidence(
            recordID: UUID,
            sourceSpeakerID: String,
            sourceType: String
        ) throws {}
        func createProfile(displayName: String, notes: String?) throws -> ParticipantProfile { fatalError() }
        func fetchAllProfiles() throws -> [ParticipantProfile] { [] }
        func updateProfile(_ profile: ParticipantProfile, displayName: String, notes: String?) throws {}
        func renameProfile(_ profile: ParticipantProfile, to newName: String) throws {}
        func deleteProfile(_ profile: ParticipantProfile) throws {}
        func deleteAllProfiles() throws {}
    }

    private final class MutatingFailingSpeakerIdentityService: SpeakerIdentityManaging {
        private let profile: ParticipantProfile

        init(profile: ParticipantProfile) {
            self.profile = profile
        }

        func bestMatch(for embedding: [Float]) throws -> SpeakerIdentityMatch? { nil }
        func learnFromDictation(recordID: UUID, segments: [DiarizedTranscriptSegment]) throws {
            profile.displayName = "Mutated after persistence"
            profile.notes = "This mutation must roll back"
            throw SpeakerLearningTestError.failed
        }
        func learnFromProfileAssignments(
            recordID: UUID,
            segments: [DiarizedTranscriptSegment],
            profileIDsBySpeakerID: [String: UUID]
        ) throws {}
        func hasTrainingEvidence(for recordID: UUID) throws -> Bool { false }
        func removeTrainingEvidence(for recordID: UUID) throws {}
        func removeTrainingEvidence(
            recordID: UUID,
            sourceSpeakerID: String,
            sourceType: String
        ) throws {}
        func createProfile(displayName: String, notes: String?) throws -> ParticipantProfile { fatalError() }
        func fetchAllProfiles() throws -> [ParticipantProfile] { [] }
        func updateProfile(_ profile: ParticipantProfile, displayName: String, notes: String?) throws {}
        func renameProfile(_ profile: ParticipantProfile, to newName: String) throws {}
        func deleteProfile(_ profile: ParticipantProfile) throws {}
        func deleteAllProfiles() throws {}
    }

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

    @Test func updateTextAppliesManualEditAndStampsUserEditedAt() throws {
        let fixture = try makeFixture()
        let record = try fixture.historyStore.save(text: "helo world", duration: 1.0, modelUsed: "test")
        #expect(record.userEditedAt == nil)

        try fixture.historyStore.updateText(record, to: "hello world")

        #expect(record.text == "hello world")
        #expect(record.wordCount == 2)
        #expect(record.userEditedAt != nil)
    }

    @Test func updateTextIgnoresUnchangedAndEmptyEdits() throws {
        let fixture = try makeFixture()
        let record = try fixture.historyStore.save(text: "hello world", duration: 1.0, modelUsed: "test")

        try fixture.historyStore.updateText(record, to: "hello world")
        #expect(record.userEditedAt == nil)

        try fixture.historyStore.updateText(record, to: "   ")
        #expect(record.text == "hello world")
        #expect(record.userEditedAt == nil)
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
        // wordCount is always computed from final text even without destination
        #expect(records.first?.wordCount == 2)
        #expect(records.first?.destinationAppName == nil)
        #expect(records.first?.destinationAppBundleID == nil)
    }

    @Test func savePersistsDestinationAppAndWordCount() throws {
        let fixture = try makeFixture()

        let record = try fixture.historyStore.save(
            text: "one two three four",
            duration: 3.0,
            modelUsed: "base",
            destinationAppName: "Cursor",
            destinationAppBundleID: "com.todesktop.230313mzl4w4u92"
        )

        #expect(record.destinationAppName == "Cursor")
        #expect(record.destinationAppBundleID == "com.todesktop.230313mzl4w4u92")
        #expect(record.wordCount == 4)

        let fetched = try #require(try fixture.historyStore.fetchRecord(with: record.id))
        #expect(fetched.destinationAppName == "Cursor")
        #expect(fetched.destinationAppBundleID == "com.todesktop.230313mzl4w4u92")
        #expect(fetched.wordCount == 4)
    }

    @Test func saveAlwaysComputesWordCountWhenDestinationIsNil() throws {
        let fixture = try makeFixture()

        let record = try fixture.historyStore.save(
            text: "hello\nworld again",
            duration: 1.0,
            modelUsed: "tiny"
        )

        #expect(record.destinationAppName == nil)
        #expect(record.destinationAppBundleID == nil)
        #expect(record.wordCount == 3)
    }

    @Test func saveUsesExplicitWordCountWhenProvided() throws {
        let fixture = try makeFixture()

        let record = try fixture.historyStore.save(
            text: "ignored for count",
            duration: 1.0,
            modelUsed: "tiny",
            wordCount: 99
        )

        #expect(record.wordCount == 99)
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

    @Test func savingDictationTrainsCurrentUserProfile() throws {
        let fixture = try makeFixture()
        let segment = DiarizedTranscriptSegment(
            speakerId: "dictation-speaker",
            speakerLabel: "",
            speakerEmbedding: [0.2, 0.4, 0.6],
            startTime: 0,
            endTime: 2,
            confidence: 0.95,
            text: ""
        )

        let record = try fixture.historyStore.save(
            text: "Profile training sample",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [segment]
        )

        let profiles = try fixture.speakerIdentityService.fetchAllProfiles()
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
        let profile = try #require(profiles.first)
        #expect(profiles.count == 1)
        #expect(profile.displayName == "Me")
        #expect(profile.isCurrentUser)
        #expect(profile.evidenceCount == 1)
        #expect(evidence.first?.recordID == record.id)
        #expect(try fixture.historyStore.hasSpeakerTrainingEvidence(for: record))
    }

    @Test func saveSucceedsAndNotifiesWhenSpeakerLearningFailsAfterPersistence() throws {
        let fixture = try makeFixture()
        let historyStore = HistoryStore(
            modelContext: fixture.modelContext,
            speakerIdentityService: FailingSpeakerIdentityService()
        )
        let segment = DiarizedTranscriptSegment(
            speakerId: "speaker",
            speakerLabel: "",
            speakerEmbedding: [0.2, 0.4],
            startTime: 0,
            endTime: 2,
            confidence: 0.9,
            text: ""
        )
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .historyStoreDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let record = try historyStore.save(
            text: "Persist despite learning failure",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [segment]
        )

        #expect(try historyStore.fetchRecord(with: record.id)?.text == "Persist despite learning failure")
        #expect(notificationCount == 1)
    }

    @Test func saveRollsBackSharedLearningMutationsWhenFallbackServiceFails() throws {
        let fixture = try makeFixture()
        let profile = ParticipantProfile(normalizedName: "original", displayName: "Original")
        fixture.modelContext.insert(profile)
        try fixture.modelContext.save()
        let historyStore = HistoryStore(
            modelContext: fixture.modelContext,
            speakerIdentityService: MutatingFailingSpeakerIdentityService(profile: profile)
        )
        let segment = DiarizedTranscriptSegment(
            speakerId: "speaker",
            speakerLabel: "",
            speakerEmbedding: [0.2, 0.4],
            startTime: 0,
            endTime: 2,
            confidence: 0.9,
            text: ""
        )

        let record = try historyStore.save(
            text: "Persist despite a mutating learning failure",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [segment]
        )

        let persistedProfile = try #require(
            fixture.modelContext.fetch(FetchDescriptor<ParticipantProfile>()).first
        )
        #expect(persistedProfile.displayName == "Original")
        #expect(persistedProfile.notes == nil)
        #expect(try historyStore.fetchRecord(with: record.id) != nil)
    }

    @Test func removingTranscriptionEvidenceRebuildsCurrentUserProfile() throws {
        let fixture = try makeFixture()
        let firstSegment = DiarizedTranscriptSegment(
            speakerId: "speaker-1",
            speakerLabel: "",
            speakerEmbedding: [1, 0],
            startTime: 0,
            endTime: 2,
            confidence: 0.9,
            text: ""
        )
        let secondSegment = DiarizedTranscriptSegment(
            speakerId: "speaker-2",
            speakerLabel: "",
            speakerEmbedding: [0, 1],
            startTime: 0,
            endTime: 3,
            confidence: 0.9,
            text: ""
        )

        let firstRecord = try fixture.historyStore.save(
            text: "First sample",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [firstSegment]
        )
        let secondRecord = try fixture.historyStore.save(
            text: "Second sample",
            duration: 3,
            modelUsed: "base",
            speakerTrainingSegments: [secondSegment]
        )

        try fixture.historyStore.removeFromSpeakerProfiles(firstRecord)

        let profile = try #require(try fixture.speakerIdentityService.fetchAllProfiles().first)
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
        #expect(profile.evidenceCount == 1)
        #expect(profile.totalEvidenceDuration == 3)
        #expect(evidence.count == 1)
        #expect(evidence.first?.recordID == secondRecord.id)
        #expect(try !fixture.historyStore.hasSpeakerTrainingEvidence(for: firstRecord))
    }

    @Test func deletingTranscriptionAlsoDeletesItsTrainingEvidence() throws {
        let fixture = try makeFixture()
        let segment = DiarizedTranscriptSegment(
            speakerId: "dictation-speaker",
            speakerLabel: "",
            speakerEmbedding: [0.3, 0.7],
            startTime: 0,
            endTime: 2,
            confidence: 0.9,
            text: ""
        )
        let record = try fixture.historyStore.save(
            text: "Delete me",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [segment]
        )

        try fixture.historyStore.delete(record)

        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
        let profile = try #require(try fixture.speakerIdentityService.fetchAllProfiles().first)
        #expect(evidence.isEmpty)
        #expect(profile.evidenceCount == 0)
        #expect(profile.centroidEmbeddingData == nil)
    }

    @Test func assigningSpeakerProfilesUpdatesPersistedDiarizedSegments() throws {
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

        let alice = try fixture.speakerIdentityService.createProfile(displayName: "Alice", notes: nil)
        let bob = try fixture.speakerIdentityService.createProfile(displayName: "Bob", notes: nil)
        try fixture.historyStore.assignSpeakerProfile(record: record, speakerID: "speaker-a", profileID: alice.id)
        try fixture.historyStore.assignSpeakerProfile(record: record, speakerID: "speaker-b", profileID: bob.id)

        let fetchedRecord = try #require(try fixture.historyStore.fetchRecord(with: record.id))
        #expect(fetchedRecord.diarizedSegments.map(\.speakerLabel) == ["Alice", "Bob"])
        #expect(fetchedRecord.diarizedSegments.map(\.speakerProfileID) == [alice.id, bob.id])

        try fixture.speakerIdentityService.updateProfile(
            alice,
            displayName: "Alicia",
            notes: "Renamed profile"
        )
        try fixture.speakerIdentityService.deleteProfile(bob)

        let rewrittenRecord = try #require(try fixture.historyStore.fetchRecord(with: record.id))
        #expect(rewrittenRecord.diarizedSegments.map(\.speakerLabel) == ["Alicia", "Speaker 2"])
        #expect(rewrittenRecord.diarizedSegments.map(\.speakerProfileID) == [alice.id, nil])
    }

    @Test func assigningSpeakerProfileLearnsFromEmbeddedSegments() throws {
        let fixture = try makeFixture()

        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","speakerEmbedding":[0.1,0.2,0.3],"startTime":0,"endTime":1.4,"confidence":0.9,"text":"hello"}]
        """

        let record = try fixture.historyStore.save(
            text: "Speaker 1: hello",
            duration: 1.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON,
            sourceKind: .manualCapture
        )

        let alice = try fixture.speakerIdentityService.createProfile(displayName: "Alice", notes: "Host")
        try fixture.historyStore.assignSpeakerProfile(
            record: record,
            speakerID: "speaker-a",
            profileID: alice.id
        )

        let profiles = try fixture.modelContext.fetch(FetchDescriptor<ParticipantProfile>())
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())

        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Alice")
        #expect(profiles.first?.notes == "Host")
        #expect(profiles.first?.evidenceCount == 1)
        #expect(profiles.first?.totalEvidenceDuration == 1.4)
        #expect(evidence.count == 1)
        #expect(evidence.first?.profile?.displayName == "Alice")
        #expect(evidence.first?.recordID == record.id)
    }

    @Test func assigningSpeakerUsesExistingProfileWithoutEligibleEvidence() throws {
        let fixture = try makeFixture()

        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","startTime":0,"endTime":0.4,"confidence":0.9,"text":"hi"}]
        """

        let record = try fixture.historyStore.save(
            text: "Speaker 1: hi",
            duration: 0.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON,
            sourceKind: .manualCapture
        )

        let alice = try fixture.speakerIdentityService.createProfile(displayName: "Alice", notes: nil)
        try fixture.historyStore.assignSpeakerProfile(
            record: record,
            speakerID: "speaker-a",
            profileID: alice.id
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
        alice.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(alice)

        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        bob.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
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

    @Test func speakerIdentityBestMatchesPreservesOrderAndRejectsInvalidEmbeddings() throws {
        let fixture = try makeFixture()

        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(alice)

        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        bob.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        bob.centroidEmbeddingData = try JSONEncoder().encode([0.0 as Float, 1.0, 0.0])
        fixture.modelContext.insert(bob)
        try fixture.modelContext.save()

        // Valid unambiguous vectors after each invalid category so early-return,
        // compaction, or index-shifting would misalign later matches.
        let embeddings: [[Float]] = [
            [0.98, 0.02, 0.0],          // 0: Alice above threshold
            [],                         // 1: empty => nil
            [0.0, 0.98, 0.0],           // 2: Bob after empty
            [0.5, 0.5],                 // 3: dimension mismatch => nil
            [0.97, 0.03, 0.0],          // 4: Alice after dimension mismatch
            [0.9, Float.nan, 0.0],      // 5: non-finite => nil
            [0.02, 0.97, 0.0],          // 6: Bob after non-finite
            [0.01, 0.01, 0.98],         // 7: no profile near enough => nil
        ]

        let matches = try fixture.speakerIdentityService.bestMatches(for: embeddings)

        #expect(matches.count == embeddings.count)

        #expect(matches[0]?.profileID == alice.id)
        #expect(matches[0]?.displayName == "Alice")
        #expect((matches[0]?.similarity ?? 0) >= 0.72)

        #expect(matches[1] == nil)

        #expect(matches[2]?.profileID == bob.id)
        #expect(matches[2]?.displayName == "Bob")
        #expect((matches[2]?.similarity ?? 0) >= 0.72)

        #expect(matches[3] == nil)

        #expect(matches[4]?.profileID == alice.id)
        #expect(matches[4]?.displayName == "Alice")
        #expect((matches[4]?.similarity ?? 0) >= 0.72)

        #expect(matches[5] == nil)

        #expect(matches[6]?.profileID == bob.id)
        #expect(matches[6]?.displayName == "Bob")
        #expect((matches[6]?.similarity ?? 0) >= 0.72)

        #expect(matches[7] == nil)


        // Single-match API is a thin ordered batch of one.
        let single = try fixture.speakerIdentityService.bestMatch(for: embeddings[0])
        #expect(single == matches[0])
        #expect(try fixture.speakerIdentityService.bestMatches(for: []).isEmpty)
    }

    @Test func speakerIdentityBestMatchesRejectsWhenSimilarityMarginIsTooSmall() throws {
        let fixture = try makeFixture()

        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0])
        fixture.modelContext.insert(alice)

        let bob = ParticipantProfile(normalizedName: "bob", displayName: "Bob")
        bob.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        bob.centroidEmbeddingData = try JSONEncoder().encode([0.99 as Float, 0.01])
        fixture.modelContext.insert(bob)
        try fixture.modelContext.save()

        let matches = try fixture.speakerIdentityService.bestMatches(for: [
            [1.0, 0.0],
            [0.0, 1.0],
        ])

        #expect(matches.count == 2)
        #expect(matches[0] == nil)
        #expect(matches[1] == nil)
    }

    @Test func speakerIdentityBestMatchesReturnsNilWhenSimilarityIsBelowThreshold() throws {
        let fixture = try makeFixture()

        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(alice)
        try fixture.modelContext.save()

        // Cosine similarity well under the 0.72 auto-match floor.
        let matches = try fixture.speakerIdentityService.bestMatches(for: [
            [0.0, 1.0, 0.0],
            [0.2, 0.2, 0.2],
        ])

        #expect(matches.count == 2)
        #expect(matches[0] == nil)
        #expect(matches[1] == nil)
    }

    @Test func speakerIdentityBestMatchesReturnsAlignedNilsForInvalidOnlyBatch() throws {
        let fixture = try makeFixture()

        // Profiles exist so a non-fast-path call would fetch/decode them.
        let alice = ParticipantProfile(normalizedName: "alice", displayName: "Alice")
        alice.embeddingSpaceIdentifier = SpeakerEmbeddingSpace.current
        alice.centroidEmbeddingData = try JSONEncoder().encode([1.0 as Float, 0.0, 0.0])
        fixture.modelContext.insert(alice)
        try fixture.modelContext.save()

        let invalidOnly: [[Float]] = [
            [],
            [0.5, Float.nan, 0.0],
            [Float.infinity, 0.0, 0.0],
        ]


        let matches = try fixture.speakerIdentityService.bestMatches(for: invalidOnly)

        #expect(matches.count == invalidOnly.count)
        #expect(matches.allSatisfy { $0 == nil })

        // A later scorable call still matches normally.
        let scorable = try fixture.speakerIdentityService.bestMatches(for: [[0.98, 0.02, 0.0]])
        #expect(scorable.count == 1)
        #expect(scorable[0]?.profileID == alice.id)
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

    // Semantic media-filter coverage only — does not prove query-plan cost.
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

    // Semantic limit/order/source-kind coverage only — does not prove query-plan cost.
    @Test func fetchMediaRecordsHonorsLimitNewestOrderAndImportedWebOnly() throws {
        let fixture = try makeFixture()

        let voice = try fixture.historyStore.save(text: "Voice only", duration: 1.0, modelUsed: "tiny")
        voice.timestamp = Date(timeIntervalSince1970: 5_000)

        let meeting = try fixture.historyStore.save(
            text: "Meeting capture",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .manualCapture,
            sourceDisplayName: "Meeting",
            managedMediaPath: "/tmp/meeting.caf"
        )
        meeting.timestamp = Date(timeIntervalSince1970: 4_000)

        let olderWeb = try fixture.historyStore.save(
            text: "Older web",
            duration: 3.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Older web",
            originalSourceURL: "https://example.com/older",
            managedMediaPath: "/tmp/older.mp4"
        )
        olderWeb.timestamp = Date(timeIntervalSince1970: 1_000)

        let middleImport = try fixture.historyStore.save(
            text: "Middle import",
            duration: 4.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "middle.mov",
            managedMediaPath: "/tmp/middle.mov"
        )
        middleImport.timestamp = Date(timeIntervalSince1970: 2_000)

        let newestWeb = try fixture.historyStore.save(
            text: "Newest web",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Newest web",
            originalSourceURL: "https://example.com/newest",
            managedMediaPath: "/tmp/newest.mp4"
        )
        newestWeb.timestamp = Date(timeIntervalSince1970: 3_000)
        try fixture.modelContext.save()

        let allMedia = try fixture.historyStore.fetchMediaRecords()
        #expect(allMedia.map(\.id) == [newestWeb.id, middleImport.id, olderWeb.id])
        #expect(allMedia.map(\.resolvedSourceKind) == [.webLink, .importedFile, .webLink])
        #expect(!allMedia.map(\.id).contains(voice.id))
        #expect(!allMedia.map(\.id).contains(meeting.id))

        let limited = try fixture.historyStore.fetchMediaRecords(limit: 2)
        #expect(limited.map(\.id) == [newestWeb.id, middleImport.id])

        let single = try fixture.historyStore.fetchMediaRecords(limit: 1)
        #expect(single.map(\.id) == [newestWeb.id])

        // Nonpositive limits short-circuit to empty (SwiftData fetchLimit 0 == unlimited).
        let zeroLimit = try fixture.historyStore.fetchMediaRecords(limit: 0)
        #expect(zeroLimit.isEmpty)

        let negativeLimit = try fixture.historyStore.fetchMediaRecords(limit: -1)
        #expect(negativeLimit.isEmpty)
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

    @Test func deleteAllClearsEvidenceAndRebuildsSpeakerProfilesWithSingleNotification() throws {
        let fixture = try makeFixture()

        let firstSegment = DiarizedTranscriptSegment(
            speakerId: "speaker-1",
            speakerLabel: "",
            speakerEmbedding: [1, 0],
            startTime: 0,
            endTime: 2,
            confidence: 0.9,
            text: ""
        )
        let secondSegment = DiarizedTranscriptSegment(
            speakerId: "speaker-2",
            speakerLabel: "",
            speakerEmbedding: [0, 1],
            startTime: 0,
            endTime: 3,
            confidence: 0.9,
            text: ""
        )

        _ = try fixture.historyStore.save(
            text: "First learned sample",
            duration: 2,
            modelUsed: "base",
            speakerTrainingSegments: [firstSegment]
        )
        _ = try fixture.historyStore.save(
            text: "Second learned sample",
            duration: 3,
            modelUsed: "base",
            speakerTrainingSegments: [secondSegment]
        )

        let profileBefore = try #require(try fixture.speakerIdentityService.fetchAllProfiles().first)
        #expect(profileBefore.isCurrentUser)
        #expect(profileBefore.evidenceCount == 2)
        #expect(profileBefore.totalEvidenceDuration == 5)
        #expect(profileBefore.centroidEmbeddingData != nil)
        #expect(try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>()).count == 2)
        #expect(try fixture.historyStore.fetchAll().count == 2)

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .historyStoreDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try fixture.historyStore.deleteAll()

        let records = try fixture.historyStore.fetchAll()
        let evidence = try fixture.modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
        let profiles = try fixture.speakerIdentityService.fetchAllProfiles()
        let profileAfter = try #require(profiles.first)

        #expect(records.isEmpty)
        #expect(evidence.isEmpty)
        #expect(profiles.count == 1)
        #expect(profileAfter.isCurrentUser)
        #expect(profileAfter.id == profileBefore.id)
        #expect(profileAfter.evidenceCount == 0)
        #expect(profileAfter.totalEvidenceDuration == 0)
        #expect(profileAfter.centroidEmbeddingData == nil)
        #expect(notificationCount == 1)
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

        // Successful single-record delete owns post-commit filesystem cleanup:
        // row is gone and managed media paths are removed before delete returns.
        #expect(try fixture.historyStore.fetchAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mediaURL.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(!FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    @Test func deleteRemovesManagedMediaPeaksSidecarImmediately() throws {
        let fixture = try makeFixture()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let mediaURL = tempDirectory.appendingPathComponent("clip.mp4")
        let thumbnailURL = tempDirectory.appendingPathComponent("clip.png")
        let peaksURL = WaveformPeaks.sidecarURL(for: mediaURL)
        try Data("media".utf8).write(to: mediaURL)
        try Data("thumb".utf8).write(to: thumbnailURL)
        try Data("[0.25,0.5,0.75]".utf8).write(to: peaksURL)

        let record = try fixture.historyStore.save(
            text: "Peaks media",
            duration: 4.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "clip.mp4",
            managedMediaPath: mediaURL.path,
            thumbnailPath: thumbnailURL.path
        )

        #expect(FileManager.default.fileExists(atPath: mediaURL.path))
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(FileManager.default.fileExists(atPath: peaksURL.path))

        try fixture.historyStore.delete(record)

        // Single-record delete owns post-commit cleanup synchronously: media,
        // thumbnail, peaks sidecar, and empty parent directory are gone when
        // delete returns.
        #expect(try fixture.historyStore.fetchAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mediaURL.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(!FileManager.default.fileExists(atPath: peaksURL.path))
        #expect(!FileManager.default.fileExists(atPath: tempDirectory.path))
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
            generatedTitle: "Roadmap Risk Review",
            aiSummary: "The product team reviewed roadmap risk areas and identified follow-up work.",
            sourceTitleOrigin: .fallback,
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
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Risk Review").count == 1)
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "follow-up work").count == 1)
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
            generatedTitle: "Beta Planning",
            sourceTitleOrigin: .fallback,
            managedMediaPath: "/tmp/zulu.mp4"
        )
        try fixture.historyStore.save(
            text: "Alpha",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Alpha Call",
            sourceTitleOrigin: .sourceMetadata,
            managedMediaPath: "/tmp/alpha.mp4"
        )

        let newest = try fixture.historyStore.fetchMediaLibrary(sort: .newest)
        let oldest = try fixture.historyStore.fetchMediaLibrary(sort: .oldest)
        let ascending = try fixture.historyStore.fetchMediaLibrary(sort: .nameAscending)
        let descending = try fixture.historyStore.fetchMediaLibrary(sort: .nameDescending)

        #expect(newest.first?.preferredTitle == "Alpha Call")
        #expect(oldest.first?.preferredTitle == "Beta Planning")
        #expect(ascending.map(\.preferredTitle) == ["Alpha Call", "Beta Planning"])
        #expect(descending.map(\.preferredTitle) == ["Beta Planning", "Alpha Call"])
    }

    // Semantic search/folder/sort coverage only — does not prove query-plan cost.
    @Test func fetchMediaLibraryPreservesSearchFolderAndNameSortSemantics() throws {
        let fixture = try makeFixture()
        let research = try fixture.historyStore.createFolder(named: "Research")
        let archive = try fixture.historyStore.createFolder(named: "Archive")

        let beta = try fixture.historyStore.save(
            text: "Body without the needle",
            originalText: "original body text",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Zulu Source",
            generatedTitle: "Beta Planning",
            aiSummary: "Summary mentions Zephyr outcomes",
            sourceTitleOrigin: .fallback,
            originalSourceURL: "https://example.com/zephyr-beta",
            managedMediaPath: "/tmp/beta.mp4",
            folderID: research.id
        )
        beta.timestamp = Date(timeIntervalSince1970: 1_000)

        let alpha = try fixture.historyStore.save(
            text: "Alpha body",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "Alpha Source",
            sourceTitleOrigin: .sourceMetadata,
            managedMediaPath: "/tmp/alpha.mov",
            folderID: archive.id
        )
        alpha.timestamp = Date(timeIntervalSince1970: 2_000)

        let voice = try fixture.historyStore.save(
            text: "Voice should never appear in media library",
            duration: 1.0,
            modelUsed: "tiny",
            generatedTitle: "Zephyr Voice"
        )
        voice.timestamp = Date(timeIntervalSince1970: 3_000)
        try fixture.modelContext.save()

        // Broadened optional-field search (title/summary/source/URL/body) + media-only.
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Zephyr").map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Beta Planning").map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Zulu Source").map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "example.com/zephyr").map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "original body").map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(query: "Alpha body").map(\.id) == [alpha.id])

        // Folder membership is independent of sort and still media-only.
        #expect(try fixture.historyStore.fetchMediaLibrary(folderID: research.id).map(\.id) == [beta.id])
        #expect(try fixture.historyStore.fetchMediaLibrary(folderID: archive.id).map(\.id) == [alpha.id])
        #expect(
            try fixture.historyStore.fetchMediaLibrary(folderID: research.id, query: "Alpha").isEmpty
        )

        let newest = try fixture.historyStore.fetchMediaLibrary(sort: .newest)
        let oldest = try fixture.historyStore.fetchMediaLibrary(sort: .oldest)
        let ascending = try fixture.historyStore.fetchMediaLibrary(sort: .nameAscending)
        let descending = try fixture.historyStore.fetchMediaLibrary(sort: .nameDescending)

        #expect(newest.map(\.id) == [alpha.id, beta.id])
        #expect(oldest.map(\.id) == [beta.id, alpha.id])
        #expect(ascending.map(\.preferredTitle) == ["Alpha Source", "Beta Planning"])
        #expect(descending.map(\.preferredTitle) == ["Beta Planning", "Alpha Source"])
        #expect(!newest.map(\.id).contains(voice.id))
    }


    // MARK: - Library sort / broadened search (B7)

    @Test func fetchTranscriptionsSortsByNewestAndOldest() throws {
        let fixture = try makeFixture()
        let older = try fixture.historyStore.save(text: "Older item", duration: 1.0, modelUsed: "tiny")
        older.timestamp = Date(timeIntervalSince1970: 1_000)
        let newer = try fixture.historyStore.save(text: "Newer item", duration: 1.0, modelUsed: "tiny")
        newer.timestamp = Date(timeIntervalSince1970: 2_000)
        try fixture.modelContext.save()

        let newest = try fixture.historyStore.fetchTranscriptions(limit: 10, sort: .newest)
        let oldest = try fixture.historyStore.fetchTranscriptions(limit: 10, sort: .oldest)

        #expect(newest.map(\.text) == ["Newer item", "Older item"])
        #expect(oldest.map(\.text) == ["Older item", "Newer item"])
    }

    @Test func fetchTranscriptionsSearchMatchesTitleSummaryAndSource() throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(
            text: "Body does not include the needle",
            duration: 1.0,
            modelUsed: "tiny",
            sourceDisplayName: "Quarterly Source Name",
            generatedTitle: "Generated Title Unique",
            aiSummary: "Summary mentions Project Zephyr outcomes"
        )
        try fixture.historyStore.save(
            text: "Unrelated transcript body",
            duration: 1.0,
            modelUsed: "tiny",
            sourceDisplayName: "Other",
            generatedTitle: "Other Title",
            aiSummary: "Nothing special"
        )

        let byTitle = try fixture.historyStore.fetchTranscriptions(
            limit: 10,
            query: "Generated Title Unique"
        )
        let bySummary = try fixture.historyStore.fetchTranscriptions(
            limit: 10,
            query: "Project Zephyr"
        )
        let bySource = try fixture.historyStore.fetchTranscriptions(
            limit: 10,
            query: "Quarterly Source"
        )
        let byBody = try fixture.historyStore.fetchTranscriptions(
            limit: 10,
            query: "does not include"
        )

        #expect(byTitle.count == 1)
        #expect(bySummary.count == 1)
        #expect(bySource.count == 1)
        #expect(byBody.count == 1)
        #expect(byTitle.first?.generatedTitle == "Generated Title Unique")
    }

    @Test func fetchTranscriptionsPaginationPreservesSortOrder() throws {
        let fixture = try makeFixture()
        for index in 0..<5 {
            let record = try fixture.historyStore.save(
                text: "Item \(index)",
                duration: 1.0,
                modelUsed: "tiny"
            )
            record.timestamp = Date(timeIntervalSince1970: TimeInterval(index * 100))
        }
        try fixture.modelContext.save()

        let firstPage = try fixture.historyStore.fetchTranscriptions(
            limit: 2,
            offset: 0,
            sort: .oldest
        )
        let secondPage = try fixture.historyStore.fetchTranscriptions(
            limit: 2,
            offset: 2,
            sort: .oldest
        )

        #expect(firstPage.map(\.text) == ["Item 0", "Item 1"])
        #expect(secondPage.map(\.text) == ["Item 2", "Item 3"])
    }

    @Test func transcriptionSnapshotReusesBroadenedSearchResultsForSummaryAndPages() async throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(
            text: "First matching body",
            duration: 2,
            modelUsed: "tiny",
            generatedTitle: "Project Zephyr"
        )
        try fixture.historyStore.save(
            text: "Second matching body",
            duration: 3,
            modelUsed: "tiny",
            aiSummary: "Zephyr follow-up"
        )
        try fixture.historyStore.save(text: "Unrelated", duration: 7, modelUsed: "tiny")

        let snapshot = try await fixture.historyStore.transcriptionSnapshot(query: "Zephyr")

        #expect(snapshot.count == 2)
        #expect(snapshot.spokenDuration == 5)
        #expect(snapshot.page(limit: 1, offset: 0)?.count == 1)
        #expect(snapshot.page(limit: 1, offset: 1)?.count == 1)
        #expect(snapshot.page(limit: 1, offset: 2)?.isEmpty == true)
    }

    @Test func cancellableHistorySearchDoesNotApplyStaleResults() async throws {
        let fixture = try makeFixture()

        // More than one search batch (64) so a cancelled search can be superseded
        // between cooperative yields without relying on wall-clock sleeps.
        for index in 0..<140 {
            fixture.modelContext.insert(
                TranscriptionRecord(
                    text: index < 70 ? "needle alpha \(index)" : "unrelated beta \(index)",
                    duration: 1,
                    modelUsed: "tiny",
                    generatedTitle: index < 70 ? "Needle Title \(index)" : "Other Title \(index)"
                )
            )
        }
        try fixture.modelContext.save()

        let staleTask = Task {
            try await fixture.historyStore.transcriptionSnapshot(query: "needle")
        }

        // Give the background worker a chance to start, then cancel before apply.
        await Task.yield()
        await Task.yield()
        staleTask.cancel()

        let freshSnapshot = try await fixture.historyStore.transcriptionSnapshot(query: "unrelated")

        var staleThrewCancellation = false
        var staleSnapshot: HistoryStore.TranscriptionSnapshot?
        do {
            staleSnapshot = try await staleTask.value
        } catch is CancellationError {
            staleThrewCancellation = true
        } catch {
            Issue.record("Unexpected stale search error: \(error)")
        }

        #expect(freshSnapshot.count == 70)
        #expect(freshSnapshot.spokenDuration == 70)
        let freshPage = try #require(freshSnapshot.page(limit: freshSnapshot.count, offset: 0))
        #expect(freshPage.count == 70)
        #expect(freshPage.allSatisfy { $0.text.contains("unrelated") })
        #expect(freshPage.contains(where: { $0.text.contains("needle") }) == false)

        if let staleSnapshot {
            // If the cancelled task already finished, its payload must still be the
            // needle set — never the superseding "unrelated" query.
            #expect(staleSnapshot.count == 70)
            #expect(staleSnapshot.spokenDuration == 70)
            let stalePage = try #require(staleSnapshot.page(limit: staleSnapshot.count, offset: 0))
            #expect(stalePage.count == 70)
            #expect(stalePage.allSatisfy { $0.text.contains("needle") })
            #expect(stalePage.contains(where: { $0.text.contains("unrelated") }) == false)
        } else {
            #expect(staleThrewCancellation)
        }
    }


    @Test func transcriptionAggregateUsesFilterAndDurationProjection() async throws {
        let fixture = try makeFixture()
        try fixture.historyStore.save(text: "Voice", duration: 2, modelUsed: "tiny")
        try fixture.historyStore.save(
            text: "Meeting",
            duration: 5,
            modelUsed: "tiny",
            sourceKind: .manualCapture
        )

        let aggregate = try await fixture.historyStore.transcriptionAggregate(filter: .voice)

        #expect(aggregate.count == 1)
        #expect(aggregate.spokenDuration == 2)
    }

    @Test func transcriptionAggregateHandlesLargeHistoryWithoutLoadingTranscriptFields() async throws {
        let fixture = try makeFixture()
        for index in 0..<200 {
            fixture.modelContext.insert(
                TranscriptionRecord(
                    text: String(repeating: "transcript \(index) ", count: 100),
                    duration: TimeInterval(index % 5),
                    modelUsed: "tiny",
                    sourceKind: index.isMultiple(of: 2) ? .voiceRecording : .manualCapture
                )
            )
        }
        try fixture.modelContext.save()

        let aggregate = try await fixture.historyStore.transcriptionAggregate(filter: .voice)

        #expect(aggregate.count == 100)
        #expect(aggregate.spokenDuration == 200)
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
