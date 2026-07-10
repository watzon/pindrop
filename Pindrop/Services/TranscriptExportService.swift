//
//  TranscriptExportService.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Per-recording export formats for Library / detail views.
enum TranscriptExportFormat: String, CaseIterable, Sendable, Equatable {
    case plainText
    case markdown
    case subtitles
    case timestamps

    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .subtitles: return "srt"
        case .timestamps: return "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .plainText:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        case .subtitles:
            return UTType(filenameExtension: "srt") ?? .plainText
        case .timestamps:
            return .json
        }
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .plainText:
            return localized("Plain Text (.txt)", locale: locale)
        case .markdown:
            return localized("Markdown (.md)", locale: locale)
        case .subtitles:
            return localized("Subtitles (.srt)", locale: locale)
        case .timestamps:
            return localized("Timestamps (.json)", locale: locale)
        }
    }

    /// Formats always available for any record.
    static var alwaysAvailable: [TranscriptExportFormat] {
        [.plainText, .markdown]
    }

    /// Formats that require diarized / timestamped segments.
    static var segmentDependent: [TranscriptExportFormat] {
        [.subtitles, .timestamps]
    }

    static func available(hasSegments: Bool) -> [TranscriptExportFormat] {
        hasSegments ? allCases : alwaysAvailable
    }
}

/// Pure export serialization + save-panel presentation for a single transcription record.
enum TranscriptExportService {
    enum ExportError: Error, LocalizedError {
        case emptyContent
        case writeFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .emptyContent:
                return "Nothing to export"
            case .writeFailed(let message):
                return message
            case .cancelled:
                return "Export cancelled"
            }
        }
    }

    // MARK: - Pure serialization

    /// Input data for export without depending on SwiftData model instances.
    struct ExportSource: Sendable, Equatable {
        var text: String
        var title: String?
        var timestamp: Date
        var aiSummary: String?
        var segments: [DiarizedTranscriptSegment]

        init(
            text: String,
            title: String? = nil,
            timestamp: Date = Date(),
            aiSummary: String? = nil,
            segments: [DiarizedTranscriptSegment] = []
        ) {
            self.text = text
            self.title = title
            self.timestamp = timestamp
            self.aiSummary = aiSummary
            self.segments = segments
        }

        init(record: TranscriptionRecord) {
            self.text = record.text
            self.title = record.preferredTitle
            self.timestamp = record.timestamp
            self.aiSummary = record.aiSummary
            self.segments = record.diarizedSegments
        }

        var hasSegments: Bool { !segments.isEmpty }
    }

    static func availableFormats(for source: ExportSource) -> [TranscriptExportFormat] {
        TranscriptExportFormat.available(hasSegments: source.hasSegments)
    }

    static func availableFormats(for record: TranscriptionRecord) -> [TranscriptExportFormat] {
        availableFormats(for: ExportSource(record: record))
    }

    static func serialize(_ source: ExportSource, format: TranscriptExportFormat) -> String {
        switch format {
        case .plainText:
            return source.text
        case .markdown:
            return formatAsMarkdown(source)
        case .subtitles:
            guard source.hasSegments else { return source.text }
            return formatAsSRT(source.segments)
        case .timestamps:
            guard source.hasSegments else { return source.text }
            return formatAsTimestampedJSON(source.segments, plainText: source.text)
        }
    }

    static func serialize(record: TranscriptionRecord, format: TranscriptExportFormat) -> String {
        serialize(ExportSource(record: record), format: format)
    }

    static func defaultFilename(
        title: String?,
        timestamp: Date,
        format: TranscriptExportFormat
    ) -> String {
        let base = sanitizedFilenameBase(title) ?? defaultDateFilename(timestamp)
        return "\(base).\(format.fileExtension)"
    }

    static func defaultFilename(for source: ExportSource, format: TranscriptExportFormat) -> String {
        defaultFilename(title: source.title, timestamp: source.timestamp, format: format)
    }

    static func defaultFilename(for record: TranscriptionRecord, format: TranscriptExportFormat) -> String {
        defaultFilename(for: ExportSource(record: record), format: format)
    }

    // MARK: - Save panel

    @MainActor
    @discardableResult
    static func presentSavePanel(
        for record: TranscriptionRecord,
        format: TranscriptExportFormat
    ) throws -> URL {
        try presentSavePanel(source: ExportSource(record: record), format: format)
    }

    @MainActor
    @discardableResult
    static func presentSavePanel(
        source: ExportSource,
        format: TranscriptExportFormat
    ) throws -> URL {
        let content = serialize(source, format: format)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.emptyContent
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = defaultFilename(for: source, format: format)
        panel.title = localized("Export", locale: Locale.current)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Formatters (shared with job output rendering)

    static func formatAsSRT(_ segments: [DiarizedTranscriptSegment]) -> String {
        segments.enumerated().map { idx, seg in
            let start = srtTimestamp(seg.startTime)
            let end = srtTimestamp(seg.endTime)
            let speaker = seg.speakerLabel.isEmpty ? "" : "\(seg.speakerLabel): "
            return "\(idx + 1)\n\(start) --> \(end)\n\(speaker)\(seg.text)"
        }.joined(separator: "\n\n")
    }

    static func srtTimestamp(_ t: TimeInterval) -> String {
        let totalMilliseconds = max(0, Int((t * 1000).rounded()))
        let h = totalMilliseconds / 3_600_000
        let m = (totalMilliseconds % 3_600_000) / 60_000
        let s = (totalMilliseconds % 60_000) / 1000
        let ms = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    static func formatAsTimestampedJSON(
        _ segments: [DiarizedTranscriptSegment],
        plainText: String
    ) -> String {
        struct Seg: Encodable {
            let start: Double
            let end: Double
            let speaker: String
            let text: String
        }
        let mapped = segments.map {
            Seg(start: $0.startTime, end: $0.endTime, speaker: $0.speakerLabel, text: $0.text)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(mapped),
              let string = String(data: data, encoding: .utf8) else {
            return plainText
        }
        return string
    }

    static func formatAsMarkdown(_ source: ExportSource) -> String {
        var lines: [String] = []
        let title = source.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }
        lines.append(source.text)
        if let summary = source.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            lines.append("")
            lines.append("## Summary")
            lines.append("")
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Filename helpers

    private static let dateFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter
    }()

    private static func defaultDateFilename(_ date: Date) -> String {
        "transcript_\(dateFilenameFormatter.string(from: date))"
    }

    private static func sanitizedFilenameBase(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = trimmed
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        if cleaned.count > 80 {
            return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}
