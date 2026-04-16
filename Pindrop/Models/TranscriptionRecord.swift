import Foundation
import SwiftData

typealias TranscriptionRecord = TranscriptionRecordSchemaV7.TranscriptionRecord
typealias MediaFolder = TranscriptionRecordSchemaV7.MediaFolder
typealias ParticipantProfile = TranscriptionRecordSchemaV7.ParticipantProfile
typealias ParticipantTrainingEvidence = TranscriptionRecordSchemaV7.ParticipantTrainingEvidence

enum TranscriptionTitleOrigin: String {
    case sourceMetadata
    case fallback
}

extension TranscriptionRecord {
    var sourceTitleOrigin: TranscriptionTitleOrigin? {
        guard let sourceTitleOriginRawValue else { return nil }
        return TranscriptionTitleOrigin(rawValue: sourceTitleOriginRawValue)
    }

    var hasSourceMetadataTitle: Bool {
        sourceTitleOrigin == .sourceMetadata
    }

    var preferredTitle: String? {
        let trimmedSourceDisplayName = sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGeneratedTitle = generatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        if hasSourceMetadataTitle, let trimmedSourceDisplayName, !trimmedSourceDisplayName.isEmpty {
            return trimmedSourceDisplayName
        }
        if let trimmedGeneratedTitle, !trimmedGeneratedTitle.isEmpty {
            return trimmedGeneratedTitle
        }
        if let trimmedSourceDisplayName, !trimmedSourceDisplayName.isEmpty {
            return trimmedSourceDisplayName
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    var resolvedSourceKind: MediaSourceKind {
        guard let sourceKindRawValue else { return .voiceRecording }
        return MediaSourceKind(rawValue: sourceKindRawValue) ?? .voiceRecording
    }

    var isVoiceTranscription: Bool {
        resolvedSourceKind == .voiceRecording
    }

    var isMediaTranscription: Bool {
        resolvedSourceKind.isMediaBacked
    }

    var managedMediaURL: URL? {
        guard let managedMediaPath, !managedMediaPath.isEmpty else { return nil }
        return URL(fileURLWithPath: managedMediaPath)
    }

    var thumbnailURL: URL? {
        guard let thumbnailPath, !thumbnailPath.isEmpty else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }

    var diarizedSegments: [DiarizedTranscriptSegment] {
        guard let diarizationSegmentsJSON,
              let data = diarizationSegmentsJSON.data(using: .utf8),
              let segments = try? JSONDecoder().decode([DiarizedTranscriptSegment].self, from: data) else {
            return []
        }
        return segments
    }

    var mediaLibrarySortName: String {
        preferredTitle ?? text
    }

    func matchesMediaLibrarySearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let searchableFields = [
            preferredTitle,
            text,
            originalText,
            sourceDisplayName,
            generatedTitle,
            aiSummary,
            originalSourceURL
        ]

        return searchableFields.contains { value in
            guard let value, !value.isEmpty else { return false }
            return value.localizedStandardContains(trimmedQuery)
        }
    }
}

extension MediaFolder {
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
