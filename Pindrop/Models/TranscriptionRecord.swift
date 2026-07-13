import Foundation
import SwiftData

typealias TranscriptionRecord = TranscriptionRecordSchemaV10.TranscriptionRecord
typealias MediaFolder = TranscriptionRecordSchemaV10.MediaFolder
typealias ParticipantProfile = TranscriptionRecordSchemaV10.ParticipantProfile
typealias ParticipantTrainingEvidence = TranscriptionRecordSchemaV10.ParticipantTrainingEvidence

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

    /// Cached word count when present; otherwise derived from `text`.
    var effectiveWordCount: Int {
        wordCount ?? text.wordCount
    }

    // MARK: - Meeting metadata helpers

    /// Distinct speaker count from diarized segments (by speakerId, falling back to label).
    var speakerCount: Int {
        let segments = diarizedSegments
        guard !segments.isEmpty else { return 0 }
        var seen = Set<String>()
        for segment in segments {
            let key = segment.speakerId.isEmpty ? segment.speakerLabel : segment.speakerId
            if !key.isEmpty {
                seen.insert(key)
            }
        }
        return seen.count
    }

    /// Whether diarization payload is present on the record.
    var isDiarized: Bool {
        diarizationSegmentsJSON != nil
    }

    /// Whether a non-empty AI summary is available.
    var hasSummary: Bool {
        guard let aiSummary else { return false }
        return !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Formatted meeting metadata line, e.g. `"3 speakers · diarized · summary ready"`.
    /// Builds from localized parts; returns an empty string when nothing applies.
    func meetingMetadataString(locale: Locale) -> String {
        var parts: [String] = []

        let count = speakerCount
        if count > 0 {
            if count == 1 {
                parts.append(localized("1 speaker", locale: locale))
            } else {
                parts.append(
                    String(format: localized("%d speakers", locale: locale), count)
                )
            }
        }

        if isDiarized {
            parts.append(localized("diarized", locale: locale))
        }

        if hasSummary {
            parts.append(localized("summary ready", locale: locale))
        }

        return parts.joined(separator: " · ")
    }
}

extension MediaFolder {
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
