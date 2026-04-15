import Foundation
import SwiftData

typealias TranscriptionRecord = TranscriptionRecordSchemaV6.TranscriptionRecord
typealias MediaFolder = TranscriptionRecordSchemaV6.MediaFolder
typealias ParticipantProfile = TranscriptionRecordSchemaV6.ParticipantProfile
typealias ParticipantTrainingEvidence = TranscriptionRecordSchemaV6.ParticipantTrainingEvidence

extension TranscriptionRecord {
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
        let candidate = (sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? sourceDisplayName
            : text
        return candidate ?? text
    }

    func matchesMediaLibrarySearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let searchableFields = [
            text,
            originalText,
            sourceDisplayName,
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
