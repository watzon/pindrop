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
    func learnFromRenameFeedback(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        labelsBySpeakerID: [String: String]
    ) throws
    func fetchAllProfiles() throws -> [ParticipantProfile]
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
        case renameFeedback
    }

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

    func learnFromRenameFeedback(
        recordID: UUID,
        segments: [DiarizedTranscriptSegment],
        labelsBySpeakerID: [String: String]
    ) throws {
        let normalizedLabelsBySpeakerID = labelsBySpeakerID.reduce(into: [String: String]()) { result, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result[entry.key] = trimmed
        }

        guard !normalizedLabelsBySpeakerID.isEmpty else { return }

        do {
            var touchedProfiles: [PersistentIdentifier: ParticipantProfile] = [:]

            for label in Set(normalizedLabelsBySpeakerID.values) {
                let profile = try getOrCreateProfile(named: label)
                touchedProfiles[profile.persistentModelID] = profile
            }

            for segment in segments {
                guard let label = normalizedLabelsBySpeakerID[segment.speakerId] else { continue }
                guard isEligibleForLearning(segment), let embedding = segment.speakerEmbedding else { continue }

                let profile = try getOrCreateProfile(named: label)
                touchedProfiles[profile.persistentModelID] = profile

                let key = evidenceKey(for: recordID, segment: segment)
                let existingEvidence = try fetchTrainingEvidence(withKey: key)
                if let previousProfile = existingEvidence?.profile {
                    touchedProfiles[previousProfile.persistentModelID] = previousProfile
                }

                let evidence = existingEvidence ?? ParticipantTrainingEvidence(
                    evidenceKey: key,
                    sourceTypeRawValue: EvidenceSource.renameFeedback.rawValue,
                    recordID: recordID,
                    sourceSpeakerID: segment.speakerId,
                    segmentStartTime: segment.startTime,
                    segmentEndTime: segment.endTime,
                    segmentDuration: segment.endTime - segment.startTime,
                    confidence: segment.confidence,
                    embeddingData: encodeEmbedding(embedding)
                )

                evidence.sourceTypeRawValue = EvidenceSource.renameFeedback.rawValue
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
        } catch let error as SpeakerIdentityError {
            throw error
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
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

    func renameProfile(_ profile: ParticipantProfile, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        profile.displayName = trimmed
        profile.normalizedName = normalizedKey(for: trimmed)
        profile.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }

    func deleteProfile(_ profile: ParticipantProfile) throws {
        do {
            let evidence = try fetchEvidence(for: profile.id)
            for item in evidence {
                modelContext.delete(item)
            }
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
                modelContext.delete(profile)
            }
            try modelContext.save()
        } catch {
            throw SpeakerIdentityError.saveFailed(error.localizedDescription)
        }
    }
}

@MainActor
@Observable
final class HistoryStore {
    
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
    
    init(modelContext: ModelContext, speakerIdentityService: SpeakerIdentityManaging? = nil) {
        self.modelContext = modelContext
        self.speakerIdentityService = speakerIdentityService
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
        folderID: UUID? = nil
    ) throws -> TranscriptionRecord {
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
            thumbnailPath: thumbnailPath
        )

        if let folderID,
           let folder = try fetchFolder(id: folderID) {
            record.folder = folder
        }
        
        modelContext.insert(record)
        
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
            return record
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
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
        case notes
    }

    func fetchTranscriptions(
        limit: Int,
        offset: Int = 0,
        query: String = "",
        filter: HistoryFilter = .all
    ) throws -> [TranscriptionRecord] {
        var descriptor = transcriptionsDescriptor(query: query, filter: filter)
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchAllTranscriptions(query: String = "", filter: HistoryFilter = .all) throws -> [TranscriptionRecord] {
        let descriptor = transcriptionsDescriptor(query: query, filter: filter)

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func countTranscriptions(query: String = "", filter: HistoryFilter = .all) throws -> Int {
        let descriptor = transcriptionsDescriptor(query: query, filter: filter)

        do {
            return try modelContext.fetchCount(descriptor)
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

    func updateSpeakerLabels(
        record: TranscriptionRecord,
        labelsBySpeakerID: [String: String]
    ) throws {
        let normalizedLabelsBySpeakerID = labelsBySpeakerID.reduce(into: [String: String]()) { result, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result[entry.key] = trimmed
        }

        guard !normalizedLabelsBySpeakerID.isEmpty else { return }

        let diarizedSegments = record.diarizedSegments
        guard !diarizedSegments.isEmpty else { return }

        var hasChanges = false
        let updatedSegments = diarizedSegments.map { segment in
            guard let updatedLabel = normalizedLabelsBySpeakerID[segment.speakerId],
                  updatedLabel != segment.speakerLabel else {
                return segment
            }

            hasChanges = true
            return DiarizedTranscriptSegment(
                speakerId: segment.speakerId,
                speakerLabel: updatedLabel,
                speakerEmbedding: segment.speakerEmbedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: segment.text
            )
        }

        guard hasChanges else { return }

        do {
            let data = try JSONEncoder().encode(updatedSegments)
            record.diarizationSegmentsJSON = String(data: data, encoding: .utf8)
            try speakerIdentityService?.learnFromRenameFeedback(
                recordID: record.id,
                segments: updatedSegments,
                labelsBySpeakerID: normalizedLabelsBySpeakerID
            )
            try modelContext.save()
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
        modelContext.delete(record)
        
        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            let records = try fetchAll()
            records.forEach(removeManagedMedia)
            try modelContext.delete(model: TranscriptionRecord.self)
            try modelContext.save()
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

    private func removeManagedMedia(for record: TranscriptionRecord) {
        let fileManager = FileManager.default
        let candidatePaths = [record.managedMediaPath, record.thumbnailPath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parentDirectories = Set<String>()
        for path in candidatePaths {
            do {
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
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

    private func transcriptionsDescriptor(
        query: String,
        filter: HistoryFilter
    ) -> FetchDescriptor<TranscriptionRecord> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortDescriptors = [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .reverse)]

        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let manualCaptureRawValue = MediaSourceKind.manualCapture.rawValue
        let importedFileRawValue = MediaSourceKind.importedFile.rawValue
        let webLinkRawValue = MediaSourceKind.webLink.rawValue

        switch (filter, trimmedQuery.isEmpty) {
        case (.all, true):
            return FetchDescriptor(sortBy: sortDescriptors)

        case (.all, false):
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

        case (.notes, _):
            // Notes are stored in a separate model — return an empty match so
            // callers that still run this descriptor under the Notes filter
            // get no transcription rows.
            let impossibleID = UUID()
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.id == impossibleID
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
