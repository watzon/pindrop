//
//  HistoryStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftData
import AppKit

extension Notification.Name {
    static let historyStoreDidChange = Notification.Name("tech.watzon.pindrop.historyStoreDidChange")
}

@MainActor
struct SpeakerIdentityMatch: Equatable {
    let profileID: UUID
    let displayName: String
    let similarity: Float
}

@MainActor
protocol SpeakerIdentityManaging: AnyObject {
    func knownSpeakers() throws -> [Speaker]
    func bestMatch(for embedding: [Float]) throws -> SpeakerIdentityMatch?
    func learnFromDictation(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment]
    ) throws
    func learnFromProfileAssignments(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        profileIDsBySpeakerID: [String: UUID]
    ) throws
    func hasTrainingEvidence(for recordID: UUID) throws -> Bool
    func removeTrainingEvidence(for recordID: UUID) throws
    func createProfile(displayName: String, notes: String?) throws -> ParticipantProfile
    func fetchAllProfiles() throws -> [ParticipantProfile]
    func updateProfile(_ profile: ParticipantProfile, displayName: String, notes: String?) throws
    func renameProfile(_ profile: ParticipantProfile, to newName: String) throws
    func deleteProfile(_ profile: ParticipantProfile) throws
    func deleteAllProfiles() throws
}

@MainActor
@Observable
final class SpeakerIdentityService: SpeakerIdentityManaging {
    enum SpeakerIdentityError: Error, LocalizedError {
        case fetchFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .fetchFailed(let message):
                return "Failed to fetch speaker identities: \(message)"
            case .saveFailed(let message):
                return "Failed to save speaker identities: \(message)"
            }
        }
    }

    private enum EvidenceSource: String {
        case dictation
        case renameFeedback
    }

    private static let currentUserProfileID = UUID(uuidString: "9A80C8F2-DBA4-4F80-8D06-54F6151EC212")!

    private static let minimumDurationForLearning: TimeInterval = 1.0
    private static let minimumConfidenceForLearning: Float = 0.45
    private static let minimumSimilarityForAutoMatch: Float = 0.72
    private static let minimumSimilarityMarginForAutoMatch: Float = 0.08

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func knownSpeakers() throws -> [Speaker] {
        do {
            let profiles = try modelContext.fetch(FetchDescriptor<ParticipantProfile>())
            return profiles.compactMap { profile in
                guard let embedding = decodeEmbedding(profile.centroidEmbeddingData), !embedding.isEmpty else {
                    return nil
                }

                return Speaker(
                    id: profile.id.uuidString,
                    label: profile.displayName,
                    embedding: embedding
                )
            }
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    func bestMatch(for embedding: [Float]) throws -> SpeakerIdentityMatch? {
        guard !embedding.isEmpty else { return nil }

        do {
            let profiles = try modelContext.fetch(FetchDescriptor<ParticipantProfile>())
            let scoredProfiles = profiles.compactMap { profile -> SpeakerIdentityMatch? in
                guard let centroid = decodeEmbedding(profile.centroidEmbeddingData), !centroid.isEmpty else {
                    return nil
                }

                let similarity = cosineSimilarity(between: embedding, and: centroid)
                guard similarity.isFinite else { return nil }

                return SpeakerIdentityMatch(
                    profileID: profile.id,
                    displayName: profile.displayName,
                    similarity: similarity
                )
            }
            .sorted { $0.similarity > $1.similarity }

            guard let bestMatch = scoredProfiles.first,
                  bestMatch.similarity >= Self.minimumSimilarityForAutoMatch else {
                return nil
            }

            if let secondBest = scoredProfiles.dropFirst().first,
               (bestMatch.similarity - secondBest.similarity) < Self.minimumSimilarityMarginForAutoMatch {
                return nil
            }

            return bestMatch
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    func learnFromProfileAssignments(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        profileIDsBySpeakerID: [String: UUID]
    ) throws {
        guard !profileIDsBySpeakerID.isEmpty else { return }

        do {
            var profilesByID: [UUID: ParticipantProfile] = [:]
            for profileID in Set(profileIDsBySpeakerID.values) {
                guard let profile = try fetchProfile(id: profileID) else { continue }
                profilesByID[profileID] = profile
            }

            try learn(
                recordID: recordID,
                segments: segments,
                source: .renameFeedback
            ) { segment in
                guard let profileID = profileIDsBySpeakerID[segment.speakerId] else { return nil }
                return profilesByID[profileID]
            }
        } catch let error as SpeakerIdentityError {
            throw error
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func learnFromDictation(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment]
    ) throws {
        guard segments.contains(where: isEligibleForLearning) else { return }

        do {
            let profile = try getOrCreateCurrentUserProfile()
            try learn(recordID: recordID, segments: segments, source: .dictation) { _ in profile }
        } catch let error as SpeakerIdentityError {
            throw error
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func hasTrainingEvidence(for recordID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<ParticipantTrainingEvidence>(
            predicate: #Predicate { $0.recordID == recordID }
        )
        descriptor.fetchLimit = 1

        do {
            return try !modelContext.fetch(descriptor).isEmpty
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    func removeTrainingEvidence(for recordID: UUID) throws {
        try removeTrainingEvidence(for: [recordID])
    }

    /// Removes training evidence for many records in one transaction: one evidence
    /// fetch, unique profile collection, evidence deletion, one rebuild per touched
    /// profile from the post-delete evidence set, and a single save.
    func removeTrainingEvidence(for recordIDs: [UUID]) throws {
        let uniqueIDs = Array(Set(recordIDs))
        guard !uniqueIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<ParticipantTrainingEvidence>(
            predicate: #Predicate<ParticipantTrainingEvidence> { evidence in
                if let recordID = evidence.recordID {
                    return uniqueIDs.contains(recordID)
                } else {
                    return false
                }
            }
        )

        do {
            let evidence = try modelContext.fetch(descriptor)
            guard !evidence.isEmpty else { return }

            let touchedProfiles = evidence.reduce(into: [PersistentIdentifier: ParticipantProfile]()) {
                result, item in
                guard let profile = item.profile else { return }
                result[profile.persistentModelID] = profile
            }

            for item in evidence {
                modelContext.delete(item)
            }

            for profile in touchedProfiles.values {
                rebuildProfile(profile)
            }
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }


    private func learn(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        source: EvidenceSource,
        profileForSegment: (DiarizedTranscriptSegment) -> ParticipantProfile?
    ) throws {
        var touchedProfiles: [PersistentIdentifier: ParticipantProfile] = [:]

        for segment in segments {
            guard isEligibleForLearning(segment),
                  let embedding = segment.speakerEmbedding,
                  let profile = profileForSegment(segment) else {
                continue
            }

            touchedProfiles[profile.persistentModelID] = profile
            let key = evidenceKey(for: recordID, segment: segment)
            let existingEvidence = try fetchTrainingEvidence(withKey: key)
            if let previousProfile = existingEvidence?.profile {
                touchedProfiles[previousProfile.persistentModelID] = previousProfile
            }

            let evidence = existingEvidence ?? ParticipantTrainingEvidence(
                evidenceKey: key,
                sourceTypeRawValue: source.rawValue,
                recordID: recordID,
                sourceSpeakerID: segment.speakerId,
                segmentStartTime: segment.startTime,
                segmentEndTime: segment.endTime,
                segmentDuration: segment.endTime - segment.startTime,
                confidence: segment.confidence,
                embeddingData: encodeEmbedding(embedding)
            )

            evidence.sourceTypeRawValue = source.rawValue
            evidence.recordID = recordID
            evidence.sourceSpeakerID = segment.speakerId
            evidence.segmentStartTime = segment.startTime
            evidence.segmentEndTime = segment.endTime
            evidence.segmentDuration = segment.endTime - segment.startTime
            evidence.confidence = segment.confidence
            evidence.embeddingData = encodeEmbedding(embedding)
            evidence.updatedAt = Date()
            evidence.profile = profile

            if existingEvidence == nil {
                modelContext.insert(evidence)
            }
        }

        for profile in touchedProfiles.values {
            rebuildProfile(profile)
        }
        if !touchedProfiles.isEmpty {
            try modelContext.save()
        }
    }

    private func getOrCreateCurrentUserProfile() throws -> ParticipantProfile {
        var currentUserDescriptor = FetchDescriptor<ParticipantProfile>(
            predicate: #Predicate { $0.isCurrentUser }
        )
        currentUserDescriptor.fetchLimit = 1

        if let profile = try modelContext.fetch(currentUserDescriptor).first {
            return profile
        }

        let profileID = Self.currentUserProfileID
        if let profile = try fetchProfile(id: profileID) {
            profile.isCurrentUser = true
            return profile
        }

        if let profile = try fetchProfile(normalizedName: "me") {
            profile.isCurrentUser = true
            return profile
        }

        let profile = ParticipantProfile(
            id: profileID,
            normalizedName: "me",
            displayName: "Me",
            isCurrentUser: true
        )
        modelContext.insert(profile)
        return profile
    }

    private func getOrCreateProfile(named displayName: String) throws -> ParticipantProfile {
        let normalizedName = normalizedKey(for: displayName)

        if let existing = try fetchProfile(normalizedName: normalizedName) {
            existing.displayName = displayName
            existing.updatedAt = Date()
            return existing
        }

        let profile = ParticipantProfile(
            normalizedName: normalizedName,
            displayName: displayName
        )
        modelContext.insert(profile)
        return profile
    }

    private func fetchProfile(normalizedName: String) throws -> ParticipantProfile? {
        let descriptor = FetchDescriptor<ParticipantProfile>(
            predicate: #Predicate { $0.normalizedName == normalizedName }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    private func fetchProfile(id: UUID) throws -> ParticipantProfile? {
        var descriptor = FetchDescriptor<ParticipantProfile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    private func fetchTrainingEvidence(withKey evidenceKey: String) throws -> ParticipantTrainingEvidence? {
        let descriptor = FetchDescriptor<ParticipantTrainingEvidence>(
            predicate: #Predicate { $0.evidenceKey == evidenceKey }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    private func fetchEvidence(for profileID: UUID) throws -> [ParticipantTrainingEvidence] {
        let descriptor = FetchDescriptor<ParticipantTrainingEvidence>(
            predicate: #Predicate { $0.profile?.id == profileID }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    private func rebuildProfile(_ profile: ParticipantProfile) {
        let evidence = (try? fetchEvidence(for: profile.id)) ?? []
        let embeddings = evidence.compactMap { decodeEmbedding($0.embeddingData) }

        profile.evidenceCount = embeddings.count
        profile.totalEvidenceDuration = evidence.map(\.segmentDuration).reduce(0, +)
        profile.centroidEmbeddingData = embeddings.isEmpty ? nil : encodeEmbedding(averageEmbedding(embeddings))
        profile.updatedAt = Date()
    }

    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }

        var totals = Array(repeating: Float.zero, count: first.count)
        var sampleCount: Float = 0

        for embedding in embeddings where embedding.count == first.count {
            for (index, value) in embedding.enumerated() {
                totals[index] += value
            }
            sampleCount += 1
        }

        guard sampleCount > 0 else { return [] }
        return totals.map { $0 / sampleCount }
    }

    private func cosineSimilarity(between lhs: [Float], and rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -.infinity }

        var dotProduct: Float = 0
        var lhsMagnitude: Float = 0
        var rhsMagnitude: Float = 0

        for index in lhs.indices {
            let lhsValue = lhs[index]
            let rhsValue = rhs[index]
            dotProduct += lhsValue * rhsValue
            lhsMagnitude += lhsValue * lhsValue
            rhsMagnitude += rhsValue * rhsValue
        }

        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return -.infinity }
        return dotProduct / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }

    private func isEligibleForLearning(_ segment: DiarizedTranscriptSegment) -> Bool {
        guard let embedding = segment.speakerEmbedding, !embedding.isEmpty else { return false }
        let duration = segment.endTime - segment.startTime
        return duration >= Self.minimumDurationForLearning && segment.confidence >= Self.minimumConfidenceForLearning
    }

    private func normalizedKey(for label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func evidenceKey(for recordID: UUID, segment: DiarizedTranscriptSegment) -> String {
        [
            recordID.uuidString,
            segment.speakerId,
            String(format: "%.3f", segment.startTime),
            String(format: "%.3f", segment.endTime)
        ].joined(separator: "|")
    }

    private func encodeEmbedding(_ embedding: [Float]) -> Data {
        (try? JSONEncoder().encode(embedding)) ?? Data()
    }

    private func decodeEmbedding(_ data: Data?) -> [Float]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([Float].self, from: data)
    }

    // MARK: - Profile Management

    /// Creates a named participant profile (without audio evidence). Useful for pre-registering
    /// known speakers so future diarization can match them by name.
    @discardableResult
    func registerParticipant(displayName: String) throws -> ParticipantProfile {
        try getOrCreateProfile(named: displayName)
    }

    func createProfile(displayName: String, notes: String? = nil) throws -> ParticipantProfile {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SpeakerIdentityError.saveFailed("Enter a name for the speaker profile.")
        }
        guard try fetchProfile(normalizedName: normalizedKey(for: trimmedName)) == nil else {
            throw SpeakerIdentityError.saveFailed("A speaker profile with that name already exists.")
        }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ParticipantProfile(
            normalizedName: normalizedKey(for: trimmedName),
            displayName: trimmedName,
            notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        )
        modelContext.insert(profile)

        do {
            try modelContext.save()
            return profile
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func fetchAllProfiles() throws -> [ParticipantProfile] {
        do {
            let descriptor = FetchDescriptor<ParticipantProfile>(
                sortBy: [SortDescriptor(\.displayName, order: .forward)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            throw SpeakerIdentityError.fetchFailed(error.localizedDescription)
        }
    }

    func updateProfile(_ profile: ParticipantProfile, displayName: String, notes: String?) throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedName = normalizedKey(for: trimmed)
        if let duplicate = try fetchProfile(normalizedName: normalizedName), duplicate.id != profile.id {
            throw SpeakerIdentityError.saveFailed("A speaker profile with that name already exists.")
        }

        profile.displayName = trimmed
        profile.normalizedName = normalizedName
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.notes = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        profile.updatedAt = Date()

        do {
            try rewriteProfileAssignments(
                profileID: profile.id,
                updatedDisplayName: profile.displayName
            )
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func renameProfile(_ profile: ParticipantProfile, to newName: String) throws {
        try updateProfile(profile, displayName: newName, notes: profile.notes)
    }

    func deleteProfile(_ profile: ParticipantProfile) throws {
        do {
            let evidence = try fetchEvidence(for: profile.id)
            for item in evidence {
                modelContext.delete(item)
            }
            try rewriteProfileAssignments(profileID: profile.id, updatedDisplayName: nil)
            modelContext.delete(profile)
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func deleteAllProfiles() throws {
        do {
            let profiles = try modelContext.fetch(FetchDescriptor<ParticipantProfile>())
            let evidence = try modelContext.fetch(FetchDescriptor<ParticipantTrainingEvidence>())
            for item in evidence {
                modelContext.delete(item)
            }
            for profile in profiles {
                try rewriteProfileAssignments(profileID: profile.id, updatedDisplayName: nil)
                modelContext.delete(profile)
            }
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    private func rewriteProfileAssignments(
        profileID: UUID,
        updatedDisplayName: String?
    ) throws {
        let records = try modelContext.fetch(FetchDescriptor<TranscriptionRecord>())

        for record in records {
            let segments = record.diarizedSegments
            guard segments.contains(where: { $0.speakerProfileID == profileID }) else { continue }

            let updatedSegments = segments.map { segment in
                guard segment.speakerProfileID == profileID else { return segment }
                return DiarizedTranscriptSegment(
                    speakerId: segment.speakerId,
                    speakerLabel: updatedDisplayName ?? segment.speakerLabel,
                    speakerProfileID: updatedDisplayName == nil ? nil : profileID,
                    speakerEmbedding: segment.speakerEmbedding,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence,
                    text: segment.text
                )
            }
            let data = try JSONEncoder().encode(updatedSegments)
            record.diarizationSegmentsJSON = String(data: data, encoding: .utf8)
        }
    }
}

@MainActor
@Observable
final class HistoryStore {

    struct TranscriptionSnapshot {
        let count: Int
        let spokenDuration: TimeInterval
        private let searchedRecords: [TranscriptionRecord]?

        fileprivate init(
            count: Int,
            spokenDuration: TimeInterval,
            searchedRecords: [TranscriptionRecord]?
        ) {
            self.count = count
            self.spokenDuration = spokenDuration
            self.searchedRecords = searchedRecords
        }

        func page(limit: Int, offset: Int) -> [TranscriptionRecord]? {
            guard let searchedRecords else { return nil }
            guard offset < searchedRecords.count else { return [] }
            let end = min(offset + limit, searchedRecords.count)
            return Array(searchedRecords[offset..<end])
        }
    }

    struct TranscriptionAggregate: Sendable {
        let count: Int
        let spokenDuration: TimeInterval
    }
    
    enum HistoryStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case searchFailed(String)
        case exportFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save transcription: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch transcriptions: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete transcription: \(message)"
            case .searchFailed(let message):
                return "Failed to search transcriptions: \(message)"
            case .exportFailed(let message):
                return "Failed to export transcriptions: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    private let speakerIdentityService: SpeakerIdentityManaging?
    private let aggregationWorker: HistoryAggregationWorker
    
    init(modelContext: ModelContext, speakerIdentityService: SpeakerIdentityManaging? = nil) {
        self.modelContext = modelContext
        self.speakerIdentityService = speakerIdentityService
        self.aggregationWorker = HistoryAggregationWorker(modelContainer: modelContext.container)
    }
    
    @discardableResult
    func save(
        text: String,
        originalText: String? = nil,
        duration: TimeInterval,
        modelUsed: String,
        enhancedWith: String? = nil,
        diarizationSegmentsJSON: String? = nil,
        sourceKind: MediaSourceKind = .voiceRecording,
        sourceDisplayName: String? = nil,
        generatedTitle: String? = nil,
        aiSummary: String? = nil,
        sourceTitleOrigin: TranscriptionTitleOrigin? = nil,
        originalSourceURL: String? = nil,
        managedMediaPath: String? = nil,
        thumbnailPath: String? = nil,
        folderID: UUID? = nil,
        destinationAppName: String? = nil,
        destinationAppBundleID: String? = nil,
        wordCount: Int? = nil,
        speakerTrainingSegments: [DiarizedTranscriptSegment]? = nil
    ) throws -> TranscriptionRecord {
        // Always persist a word count for the final text; callers may pass an
        // explicit value (e.g. pre-computed) but we default to String.wordCount.
        let resolvedWordCount = wordCount ?? text.wordCount
        let record = TranscriptionRecord(
            text: text,
            originalText: originalText,
            duration: duration,
            modelUsed: modelUsed,
            enhancedWith: enhancedWith,
            diarizationSegmentsJSON: diarizationSegmentsJSON,
            sourceKind: sourceKind,
            sourceDisplayName: sourceDisplayName,
            generatedTitle: generatedTitle,
            aiSummary: aiSummary,
            sourceTitleOriginRawValue: sourceTitleOrigin?.rawValue,
            originalSourceURL: originalSourceURL,
            managedMediaPath: managedMediaPath,
            thumbnailPath: thumbnailPath,
            destinationAppName: destinationAppName,
            destinationAppBundleID: destinationAppBundleID,
            wordCount: resolvedWordCount
        )

        if let folderID,
           let folder = try fetchFolder(id: folderID) {
            record.folder = folder
        }
        
        modelContext.insert(record)

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }

        // The record is durable at this point. Notify consumers before attempting
        // optional speaker learning so a learning failure cannot report the save as
        // failed or leave history views stale.
        NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)

        let dictationTrainingSegments = speakerTrainingSegments ?? record.diarizedSegments
        if sourceKind == .voiceRecording, !dictationTrainingSegments.isEmpty {
            learnFromDictationBestEffort(
                recordID: record.id,
                segments: dictationTrainingSegments
            )
        }

        return record
    }
    
    func fetchAll() throws -> [TranscriptionRecord] {
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func fetch(limit: Int) throws -> [TranscriptionRecord] {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchVoiceTranscriptions(
        limit: Int,
        offset: Int = 0,
        query: String = ""
    ) throws -> [TranscriptionRecord] {
        var descriptor = voiceTranscriptionsDescriptor(query: query)
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchAllVoiceTranscriptions(query: String = "") throws -> [TranscriptionRecord] {
        let descriptor = voiceTranscriptionsDescriptor(query: query)

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func countVoiceTranscriptions(query: String = "") throws -> Int {
        let descriptor = voiceTranscriptionsDescriptor(query: query)

        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Unified fetch (all source kinds with optional filtering)

    enum HistoryFilter: Equatable, Sendable {
        case all
        case voice
        case meetings
        case media
    }

    func fetchTranscriptions(
        limit: Int,
        offset: Int = 0,
        query: String = "",
        filter: HistoryFilter = .all,
        sort: MediaLibrarySortMode = .newest
    ) throws -> [TranscriptionRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty search can paginate at the SQL layer. Non-empty search matches
        // title/summary/source in memory (Core Data cannot SQL-generate
        // optional-string CONTAINS via #Predicate coalescing).
        if trimmedQuery.isEmpty {
            var descriptor = transcriptionsDescriptor(query: "", filter: filter, sort: sort)
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            do {
                return try modelContext.fetch(descriptor)
            } catch {
                throw HistoryStoreError.fetchFailed(error.localizedDescription)
            }
        }

        let allMatching = try fetchAllTranscriptions(query: trimmedQuery, filter: filter, sort: sort)
        guard offset < allMatching.count else { return [] }
        let end = min(offset + limit, allMatching.count)
        return Array(allMatching[offset..<end])
    }

    func fetchAllTranscriptions(
        query: String = "",
        filter: HistoryFilter = .all,
        sort: MediaLibrarySortMode = .newest
    ) throws -> [TranscriptionRecord] {
        // Filter + sort in SQL; broaden search in memory for optional fields.
        let descriptor = transcriptionsDescriptor(query: "", filter: filter, sort: sort)

        do {
            var records = try modelContext.fetch(descriptor)
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                // Parity with media-library search (title/summary/source + body).
                records = records.filter { $0.matchesMediaLibrarySearch(trimmedQuery) }
            }
            return records
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func countTranscriptions(
        query: String = "",
        filter: HistoryFilter = .all,
        sort: MediaLibrarySortMode = .newest
    ) throws -> Int {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            let descriptor = transcriptionsDescriptor(query: "", filter: filter, sort: sort)
            do {
                return try modelContext.fetchCount(descriptor)
            } catch {
                throw HistoryStoreError.fetchFailed(error.localizedDescription)
            }
        }
        return try fetchAllTranscriptions(query: trimmedQuery, filter: filter, sort: sort).count
    }

    /// Returns the count and total duration for a filter without loading transcript
    /// bodies. Searches intentionally use `transcriptionSnapshot` so their in-memory
    /// matching work is performed once and reused for pagination.
    func transcriptionAggregate(filter: HistoryFilter = .all) async throws -> TranscriptionAggregate {
        do {
            return try await aggregationWorker.aggregate(filter: filter)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    /// Produces one reload-scoped result. Empty searches use store-level count and
    /// duration projections; non-empty searches match off the main actor once so
    /// count, duration, and every page share the same result set.
    func transcriptionSnapshot(
        query: String = "",
        filter: HistoryFilter = .all,
        sort: MediaLibrarySortMode = .newest
    ) async throws -> TranscriptionSnapshot {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            let aggregate = try await transcriptionAggregate(filter: filter)
            return TranscriptionSnapshot(
                count: aggregate.count,
                spokenDuration: aggregate.spokenDuration,
                searchedRecords: nil
            )
        }

        let searchResult: HistorySearchResult
        do {
            searchResult = try await aggregationWorker.search(
                query: trimmedQuery,
                filter: filter,
                sort: sort
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HistoryStoreError.searchFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let records = try fetchTranscriptions(ids: searchResult.matchingIDs)
        return TranscriptionSnapshot(
            count: searchResult.matchingIDs.count,
            spokenDuration: searchResult.spokenDuration,
            searchedRecords: records
        )
    }

    /// Hydrates main-context records for an ordered ID list produced by a background search.
    func fetchTranscriptions(ids: [UUID]) throws -> [TranscriptionRecord] {
        guard !ids.isEmpty else { return [] }

        let uniqueIDs = Array(Set(ids))
        let predicate = #Predicate<TranscriptionRecord> { record in
            uniqueIDs.contains(record.id)
        }
        let descriptor = FetchDescriptor<TranscriptionRecord>(predicate: predicate)

        do {
            let fetched = try modelContext.fetch(descriptor)
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            return ids.compactMap { byID[$0] }
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchRecord(with id: UUID) throws -> TranscriptionRecord? {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            predicate: #Predicate<TranscriptionRecord> { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    /// Attaches (or clears) the managed media path on an existing record after async encode.
    /// - Returns: `true` if the record was found and updated; `false` if no matching record exists
    ///   (caller should clean up any unlinked media files).
    @discardableResult
    func updateManagedMediaPath(for recordID: UUID, path: String?) throws -> Bool {
        guard let record = try fetchRecord(with: recordID) else {
            Log.app.warning("updateManagedMediaPath: record \(recordID) not found")
            return false
        }
        record.managedMediaPath = path
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
            return true
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    /// Lightweight projection used by dictation-audio retention maintenance.
    /// Avoids loading full transcript bodies for expiry sweeps.
    struct ExpiredDictationMediaCandidate: Sendable, Equatable {
        let recordID: UUID
        let mediaPath: String
    }

    /// Fetches a bounded page of voice-recording rows whose managed media is older than `cutoff`.
    /// Only `id` / path / timestamp fields are needed for deletion; transcript bodies stay unloaded.
    func fetchExpiredDictationMediaCandidates(
        olderThan cutoff: Date,
        limit: Int
    ) throws -> [ExpiredDictationMediaCandidate] {
        let pageLimit = max(limit, 0)
        guard pageLimit > 0 else { return [] }

        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let predicate = #Predicate<TranscriptionRecord> { record in
            (record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue)
                && record.timestamp < cutoff
                && record.managedMediaPath != nil
        }

        var descriptor = FetchDescriptor<TranscriptionRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = pageLimit
        descriptor.propertiesToFetch = [\.id, \.managedMediaPath, \.timestamp, \.sourceKindRawValue]

        do {
            let records = try modelContext.fetch(descriptor)
            var candidates: [ExpiredDictationMediaCandidate] = []
            candidates.reserveCapacity(min(records.count, pageLimit))
            for record in records {
                // Preserve empty/whitespace paths so the sweep can still clear the field
                // and the page advances; only non-empty paths need filesystem deletion.
                let path = record.managedMediaPath?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                candidates.append(
                    ExpiredDictationMediaCandidate(recordID: record.id, mediaPath: path)
                )
            }
            return candidates
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    /// Clears `managedMediaPath` for the given record IDs in one save.
    /// Missing IDs are ignored. Returns the number of rows updated.
    @discardableResult
    func clearManagedMediaPaths(for recordIDs: [UUID]) throws -> Int {
        guard !recordIDs.isEmpty else { return 0 }

        let uniqueIDs = Array(Set(recordIDs))
        let predicate = #Predicate<TranscriptionRecord> { record in
            uniqueIDs.contains(record.id)
        }
        let descriptor = FetchDescriptor<TranscriptionRecord>(predicate: predicate)

        do {
            let records = try modelContext.fetch(descriptor)
            var updated = 0
            for record in records where record.managedMediaPath != nil {
                record.managedMediaPath = nil
                updated += 1
            }
            guard updated > 0 else { return 0 }
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
            return updated
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    /// Persists pending model changes without inserting a new record.
    func saveContext() throws {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func fetchMediaRecords(limit: Int? = nil) throws -> [TranscriptionRecord] {
        let records = try fetchAll().filter(\.isMediaTranscription)
        if let limit {
            return Array(records.prefix(limit))
        }
        return records
    }

    func fetchFolders() throws -> [MediaFolder] {
        let descriptor = FetchDescriptor<MediaFolder>()

        do {
            return try modelContext.fetch(descriptor).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func createFolder(named name: String) throws -> MediaFolder {
        let normalizedName = try normalizeFolderName(name)
        guard try !folderNameExists(normalizedName) else {
            throw HistoryStoreError.saveFailed("A folder named \"\(normalizedName)\" already exists.")
        }

        let folder = MediaFolder(name: normalizedName)
        modelContext.insert(folder)

        do {
            try modelContext.save()
            return folder
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func renameFolder(_ folder: MediaFolder, to name: String) throws {
        let normalizedName = try normalizeFolderName(name)
        let existingFolders = try fetchFolders()
        let duplicate = existingFolders.contains {
            $0.id != folder.id && $0.trimmedName.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicate else {
            throw HistoryStoreError.saveFailed("A folder named \"\(normalizedName)\" already exists.")
        }

        folder.name = normalizedName
        folder.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func deleteFolder(_ folder: MediaFolder) throws {
        let records = try fetchMediaRecords().filter { $0.folder?.id == folder.id }
        records.forEach { $0.folder = nil }
        modelContext.delete(folder)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }

    func assign(record: TranscriptionRecord, to folder: MediaFolder) throws {
        record.folder = folder
        folder.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func removeFromFolder(record: TranscriptionRecord) throws {
        record.folder?.updatedAt = Date()
        record.folder = nil

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func assignSpeakerProfile(
        record: TranscriptionRecord,
        speakerID: String,
        profileID: UUID
    ) throws {
        let diarizedSegments = record.diarizedSegments
        guard !diarizedSegments.isEmpty, !speakerID.isEmpty else { return }

        var descriptor = FetchDescriptor<ParticipantProfile>(
            predicate: #Predicate { $0.id == profileID }
        )
        descriptor.fetchLimit = 1
        guard let profile = try modelContext.fetch(descriptor).first else {
            throw HistoryStoreError.saveFailed("The selected speaker profile no longer exists.")
        }

        let updatedSegments = diarizedSegments.map { segment in
            guard segment.speakerId == speakerID else {
                return segment
            }

            return DiarizedTranscriptSegment(
                speakerId: segment.speakerId,
                speakerLabel: profile.displayName,
                speakerProfileID: profile.id,
                speakerEmbedding: segment.speakerEmbedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: segment.text
            )
        }

        do {
            let data = try JSONEncoder().encode(updatedSegments)
            record.diarizationSegmentsJSON = String(data: data, encoding: .utf8)
            try speakerIdentityService?.learnFromProfileAssignments(
                recordID: record.id,
                segments: updatedSegments,
                profileIDsBySpeakerID: [speakerID: profileID]
            )
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func createAndAssignSpeakerProfile(
        record: TranscriptionRecord,
        speakerID: String,
        displayName: String,
        notes: String?
    ) throws -> ParticipantProfile {
        guard let speakerIdentityService else {
            throw HistoryStoreError.saveFailed("Speaker profiles are unavailable.")
        }

        do {
            let profile = try speakerIdentityService.createProfile(
                displayName: displayName,
                notes: notes
            )
            try assignSpeakerProfile(record: record, speakerID: speakerID, profileID: profile.id)
            return profile
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func hasSpeakerTrainingEvidence(for record: TranscriptionRecord) throws -> Bool {
        try speakerIdentityService?.hasTrainingEvidence(for: record.id) ?? false
    }

    func removeFromSpeakerProfiles(_ record: TranscriptionRecord) throws {
        do {
            try speakerIdentityService?.removeTrainingEvidence(for: record.id)
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func fetchMediaLibrary(
        folderID: UUID? = nil,
        query: String = "",
        sort: MediaLibrarySortMode = .newest
    ) throws -> [TranscriptionRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var records = try fetchMediaRecords()

        if let folderID {
            records = records.filter { $0.folder?.id == folderID }
        }

        if !trimmedQuery.isEmpty {
            records = records.filter { $0.matchesMediaLibrarySearch(trimmedQuery) }
        }

        return sortMediaRecords(records, sort: sort)
    }
    
    func delete(_ record: TranscriptionRecord) throws {
        removeManagedMedia(for: record)
        try speakerIdentityService?.removeTrainingEvidence(for: record.id)
        modelContext.delete(record)
        
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            let records = try fetchAll()
            // Snapshot filesystem paths before mutating the store so media cleanup
            // can run off-main after a successful DB commit without rereading models.
            let managedMediaPaths = records.flatMap(managedMediaPaths(for:))
            let recordIDs = records.map(\.id)

            if let speakerIdentityService = speakerIdentityService as? SpeakerIdentityService {
                try speakerIdentityService.removeTrainingEvidence(for: recordIDs)
            } else {
                // Protocol seam (tests / alternate services): preserve per-ID API.
                for recordID in recordIDs {
                    try speakerIdentityService?.removeTrainingEvidence(for: recordID)
                }
            }

            try modelContext.delete(model: TranscriptionRecord.self)
            try modelContext.save()

            // DB is durable first; filesystem cleanup is best-effort off-main so a
            // mid-delete crash cannot leave records pointing at already-removed files.
            Self.scheduleManagedMediaRemoval(paths: managedMediaPaths)

            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }

    
    func search(query: String) throws -> [TranscriptionRecord] {
        let predicate = #Predicate<TranscriptionRecord> { record in
            record.text.localizedStandardContains(query)
        }
        
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.searchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Export Methods
    
    func exportToPlainText(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "transcription_history.txt"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        var content = "Transcription History Export\n"
        content += "Generated: \(dateFormatter.string(from: Date()))\n"
        content += "Total Records: \(recordsToExport.count)\n"
        content += String(repeating: "=", count: 80) + "\n\n"
        
        for (index, record) in recordsToExport.enumerated() {
            content += "Record \(index + 1)\n"
            content += "Timestamp: \(dateFormatter.string(from: record.timestamp))\n"
            content += "Duration: \(String(format: "%.2f", record.duration))s\n"
            content += "Model: \(record.modelUsed)\n"
            if let originalText = record.originalText, originalText != record.text {
                content += "Original:\n\(originalText)\n\n"
            }
            content += "Enhanced:\n\(record.text)\n"
            content += String(repeating: "-", count: 80) + "\n\n"
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    func exportToJSON(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "transcription_history.json"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let originalText: String?
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
            let wasEnhanced: Bool
        }

        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }

        let dateFormatter = ISO8601DateFormatter()

        let exportRecords = recordsToExport.map { record in
            ExportRecord(
                id: record.id.uuidString,
                text: record.text,
                originalText: record.originalText,
                timestamp: dateFormatter.string(from: record.timestamp),
                duration: record.duration,
                modelUsed: record.modelUsed,
                wasEnhanced: record.wasEnhanced
            )
        }
        
        let exportData = ExportData(
            exportDate: dateFormatter.string(from: Date()),
            totalRecords: recordsToExport.count,
            records: exportRecords
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: url)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    func exportToCSV(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "transcription_history.csv"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        let dateFormatter = ISO8601DateFormatter()

        var csvContent = "ID,Timestamp,Duration,Model,Original Text,Enhanced Text,Was Enhanced\n"

        for record in recordsToExport {
            let escapedOriginal = (record.originalText ?? "")
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            let escapedText = record.text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            let row = [
                record.id.uuidString,
                dateFormatter.string(from: record.timestamp),
                String(format: "%.2f", record.duration),
                record.modelUsed,
                "\"\(escapedOriginal)\"",
                "\"\(escapedText)\"",
                record.wasEnhanced ? "true" : "false"
            ].joined(separator: ",")

            csvContent += row + "\n"
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }

    private func managedMediaPaths(for record: TranscriptionRecord) -> [String] {
        [record.managedMediaPath, record.thumbnailPath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func removeManagedMedia(for record: TranscriptionRecord) {
        Self.removeManagedMediaAssets(at: managedMediaPaths(for: record))
    }

    /// Fire-and-forget filesystem cleanup after the store transaction commits.
    private static func scheduleManagedMediaRemoval(paths: [String]) {
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) {
            Self.removeManagedMediaAssets(at: paths)
        }
    }

    /// Shared path-based managed-media + peaks + empty-parent cleanup.
    /// `nonisolated` so delete-all can run it off the main actor after DB commit.
    nonisolated private static func removeManagedMediaAssets(at paths: [String]) {
        let fileManager = FileManager.default
        var parentDirectories = Set<String>()
        for path in paths {
            do {
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
                }
                // Remove waveform peaks sidecar next to managed audio when present.
                let audioURL = URL(fileURLWithPath: path)
                let peaksURL = WaveformPeaks.sidecarURL(for: audioURL)
                if fileManager.fileExists(atPath: peaksURL.path) {
                    try fileManager.removeItem(at: peaksURL)
                }
                parentDirectories.insert((path as NSString).deletingLastPathComponent)
            } catch {
                Log.app.warning("Failed to remove managed media asset at \(path): \(error.localizedDescription)")
            }
        }

        for directory in parentDirectories where !directory.isEmpty {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory)
                if contents.isEmpty {
                    try fileManager.removeItem(atPath: directory)
                }
            } catch {
                Log.app.debug("Skipping managed media directory cleanup for \(directory): \(error.localizedDescription)")
            }
        }
    }


    private func learnFromDictationBestEffort(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment]
    ) {
        // Production learning gets a dedicated context so failed learning changes
        // are discarded with that context rather than remaining pending alongside
        // the saved transcription. Custom test/alternate services keep their
        // injected seam, with an explicit rollback of the shared context on error.
        let usesIsolatedContext = speakerIdentityService is SpeakerIdentityService

        do {
            if usesIsolatedContext {
                let learningContext = ModelContext(modelContext.container)
                let learningService = SpeakerIdentityService(modelContext: learningContext)
                try learningService.learnFromDictation(recordID: recordID, segments: segments)
            } else {
                try speakerIdentityService?.learnFromDictation(recordID: recordID, segments: segments)
            }
        } catch {
            if !usesIsolatedContext {
                modelContext.rollback()
            }
            Log.app.warning(
                "Saved transcription \(recordID) but speaker learning failed: \(error.localizedDescription)"
            )
        }
    }

    private func fetchFolder(id: UUID) throws -> MediaFolder? {
        let folders = try fetchFolders()
        return folders.first { $0.id == id }
    }

    private func folderNameExists(_ name: String) throws -> Bool {
        let folders = try fetchFolders()
        return folders.contains {
            $0.trimmedName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func normalizeFolderName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HistoryStoreError.saveFailed("Folder name cannot be empty.")
        }
        return trimmedName
    }

    private func voiceTranscriptionsDescriptor(query: String) -> FetchDescriptor<TranscriptionRecord> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let sortDescriptors = [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .reverse)]

        if trimmedQuery.isEmpty {
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        }

        let predicate = #Predicate<TranscriptionRecord> { record in
            (record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue)
                && record.text.localizedStandardContains(trimmedQuery)
        }
        return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
    }

    private func transcriptionsSortDescriptors(
        for sort: MediaLibrarySortMode
    ) -> [SortDescriptor<TranscriptionRecord>] {
        // Library list currently exposes newest/oldest. Name sorts fall back to
        // newest-first at the SQL level (media library keeps its own in-memory sort).
        switch sort {
        case .oldest:
            return [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .forward)]
        case .newest, .nameAscending, .nameDescending:
            return [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .reverse)]
        }
    }

    private func transcriptionsDescriptor(
        query: String,
        filter: HistoryFilter,
        sort: MediaLibrarySortMode = .newest
    ) -> FetchDescriptor<TranscriptionRecord> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortDescriptors = transcriptionsSortDescriptors(for: sort)

        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let manualCaptureRawValue = MediaSourceKind.manualCapture.rawValue
        let importedFileRawValue = MediaSourceKind.importedFile.rawValue
        let webLinkRawValue = MediaSourceKind.webLink.rawValue

        switch (filter, trimmedQuery.isEmpty) {
        case (.all, true):
            return FetchDescriptor(sortBy: sortDescriptors)

        case (.all, false):
            // Text-only SQL path kept for any callers that still pass a query
            // into the descriptor. `fetchTranscriptions` prefers in-memory
            // matching via `matchesLibrarySearch` for optional title/summary/source.
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.text.localizedStandardContains(trimmedQuery)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.voice, true):
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.voice, false):
            let predicate = #Predicate<TranscriptionRecord> { record in
                (record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue)
                    && record.text.localizedStandardContains(trimmedQuery)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.meetings, true):
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == manualCaptureRawValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.meetings, false):
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == manualCaptureRawValue
                    && record.text.localizedStandardContains(trimmedQuery)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.media, true):
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == importedFileRawValue
                    || record.sourceKindRawValue == webLinkRawValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)

        case (.media, false):
            let predicate = #Predicate<TranscriptionRecord> { record in
                (record.sourceKindRawValue == importedFileRawValue
                    || record.sourceKindRawValue == webLinkRawValue)
                    && record.text.localizedStandardContains(trimmedQuery)
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        }
    }

    private func sortMediaRecords(
        _ records: [TranscriptionRecord],
        sort: MediaLibrarySortMode
    ) -> [TranscriptionRecord] {
        switch sort {
        case .newest:
            return records.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return records.sorted { $0.timestamp < $1.timestamp }
        case .nameAscending:
            return records.sorted {
                $0.mediaLibrarySortName.localizedStandardCompare($1.mediaLibrarySortName) == .orderedAscending
            }
        case .nameDescending:
            return records.sorted {
                $0.mediaLibrarySortName.localizedStandardCompare($1.mediaLibrarySortName) == .orderedDescending
            }
        }
    }
}

/// A dedicated SwiftData executor for history header aggregates and non-empty
/// library search. Keeps O(N) duration projection and text matching off the
/// main context/actor while empty-query SQL pagination stays on the store.
@ModelActor
private actor HistoryAggregationWorker {
    private static let searchBatchSize = 64

    func aggregate(
        filter: HistoryStore.HistoryFilter
    ) throws -> HistoryStore.TranscriptionAggregate {
        let descriptor = aggregateDescriptor(for: filter)
        let count = try modelContext.fetchCount(descriptor)
        var durationDescriptor = descriptor
        durationDescriptor.propertiesToFetch = [\.duration]
        let spokenDuration = try modelContext.fetch(durationDescriptor)
            .reduce(0) { $0 + max(0, $1.duration) }

        return HistoryStore.TranscriptionAggregate(
            count: count,
            spokenDuration: spokenDuration
        )
    }

    /// Filter-scoped fetch + broadened text match + duration reduce, with
    /// cooperative cancellation between batches.
    func search(
        query: String,
        filter: HistoryStore.HistoryFilter,
        sort: MediaLibrarySortMode
    ) async throws -> HistorySearchResult {
        try Task.checkCancellation()

        let descriptor = searchDescriptor(filter: filter, sort: sort)
        let candidates = try modelContext.fetch(descriptor)
        var matchingIDs: [UUID] = []
        matchingIDs.reserveCapacity(min(candidates.count, 256))
        var spokenDuration: TimeInterval = 0

        var index = 0
        while index < candidates.count {
            try Task.checkCancellation()
            let end = min(index + Self.searchBatchSize, candidates.count)
            for record in candidates[index..<end] {
                if Self.matchesMediaLibrarySearch(record, query: query) {
                    matchingIDs.append(record.id)
                    spokenDuration += max(0, record.duration)
                }
            }
            index = end
            // Yield so a superseded search generation can cancel between batches.
            await Task.yield()
        }

        return HistorySearchResult(
            matchingIDs: matchingIDs,
            spokenDuration: spokenDuration
        )
    }

    private func aggregateDescriptor(
        for filter: HistoryStore.HistoryFilter
    ) -> FetchDescriptor<TranscriptionRecord> {
        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let manualCaptureRawValue = MediaSourceKind.manualCapture.rawValue
        let importedFileRawValue = MediaSourceKind.importedFile.rawValue
        let webLinkRawValue = MediaSourceKind.webLink.rawValue

        switch filter {
        case .all:
            return FetchDescriptor<TranscriptionRecord>()
        case .voice:
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue
            }
            return FetchDescriptor(predicate: predicate)
        case .meetings:
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == manualCaptureRawValue
            }
            return FetchDescriptor(predicate: predicate)
        case .media:
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == importedFileRawValue
                    || record.sourceKindRawValue == webLinkRawValue
            }
            return FetchDescriptor(predicate: predicate)
        }
    }

    private func searchDescriptor(
        filter: HistoryStore.HistoryFilter,
        sort: MediaLibrarySortMode
    ) -> FetchDescriptor<TranscriptionRecord> {
        // Mirror HistoryStore SQL filter + sort; broadened text match stays in memory.
        let sortDescriptors: [SortDescriptor<TranscriptionRecord>]
        switch sort {
        case .oldest:
            sortDescriptors = [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .forward)]
        case .newest, .nameAscending, .nameDescending:
            sortDescriptors = [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .reverse)]
        }

        var descriptor = aggregateDescriptor(for: filter)
        descriptor.sortBy = sortDescriptors
        // Prefer the fields used by matching/duration; SwiftData may still fault others.
        descriptor.propertiesToFetch = [
            \.id,
            \.duration,
            \.timestamp,
            \.text,
            \.originalText,
            \.sourceDisplayName,
            \.generatedTitle,
            \.aiSummary,
            \.originalSourceURL,
            \.sourceTitleOriginRawValue
        ]
        return descriptor
    }

    /// Parity with `TranscriptionRecord.matchesMediaLibrarySearch` / preferredTitle.
    private static func matchesMediaLibrarySearch(
        _ record: TranscriptionRecord,
        query: String
    ) -> Bool {
        let searchableFields = [
            preferredTitle(for: record),
            record.text,
            record.originalText,
            record.sourceDisplayName,
            record.generatedTitle,
            record.aiSummary,
            record.originalSourceURL
        ]

        return searchableFields.contains { value in
            guard let value, !value.isEmpty else { return false }
            return value.localizedStandardContains(query)
        }
    }

    private static func preferredTitle(for record: TranscriptionRecord) -> String? {
        let trimmedSourceDisplayName = record.sourceDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGeneratedTitle = record.generatedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSourceMetadataTitle = record.sourceTitleOriginRawValue
            == TranscriptionTitleOrigin.sourceMetadata.rawValue

        if hasSourceMetadataTitle,
           let trimmedSourceDisplayName,
           !trimmedSourceDisplayName.isEmpty {
            return trimmedSourceDisplayName
        }
        if let trimmedGeneratedTitle, !trimmedGeneratedTitle.isEmpty {
            return trimmedGeneratedTitle
        }
        if let trimmedSourceDisplayName, !trimmedSourceDisplayName.isEmpty {
            return trimmedSourceDisplayName
        }

        let trimmedText = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}

private struct HistorySearchResult: Sendable {
    let matchingIDs: [UUID]
    let spokenDuration: TimeInterval
}
