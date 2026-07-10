//
//  TranscriptExportServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct TranscriptExportServiceTests {
    private func makeSegment(
        speakerId: String = "spk_0",
        speakerLabel: String = "Speaker 1",
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) -> DiarizedTranscriptSegment {
        DiarizedTranscriptSegment(
            speakerId: speakerId,
            speakerLabel: speakerLabel,
            startTime: start,
            endTime: end,
            confidence: 0.9,
            text: text
        )
    }

    @Test func availableFormatsWithoutSegmentsAreTxtAndMarkdownOnly() {
        let source = TranscriptExportService.ExportSource(text: "Hello world")
        let formats = TranscriptExportService.availableFormats(for: source)
        #expect(formats == [.plainText, .markdown])
    }

    @Test func availableFormatsWithSegmentsIncludeSrtAndJson() {
        let source = TranscriptExportService.ExportSource(
            text: "Hello",
            segments: [makeSegment(start: 0, end: 1, text: "Hello")]
        )
        let formats = TranscriptExportService.availableFormats(for: source)
        #expect(formats == TranscriptExportFormat.allCases)
        #expect(formats.contains(.subtitles))
        #expect(formats.contains(.timestamps))
    }

    @Test func plainTextSerializationReturnsBody() {
        let source = TranscriptExportService.ExportSource(text: "Body text")
        #expect(TranscriptExportService.serialize(source, format: .plainText) == "Body text")
    }

    @Test func markdownSerializationIncludesTitleAndSummary() {
        let source = TranscriptExportService.ExportSource(
            text: "Meeting notes body",
            title: "Weekly Sync",
            aiSummary: "Discussed roadmap"
        )
        let markdown = TranscriptExportService.serialize(source, format: .markdown)
        #expect(markdown.contains("# Weekly Sync"))
        #expect(markdown.contains("Meeting notes body"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("Discussed roadmap"))
    }

    @Test func srtSerializationProducesCorrectTimingLines() {
        let segments = [
            makeSegment(start: 0, end: 1.5, text: "Hello there"),
            makeSegment(
                speakerId: "spk_1",
                speakerLabel: "Speaker 2",
                start: 65.25,
                end: 70,
                text: "Next line"
            ),
        ]
        let srt = TranscriptExportService.formatAsSRT(segments)

        #expect(srt.contains("1\n00:00:00,000 --> 00:00:01,500\nSpeaker 1: Hello there"))
        #expect(srt.contains("2\n00:01:05,250 --> 00:01:10,000\nSpeaker 2: Next line"))
    }

    @Test func srtTimestampFormatsHoursMinutesSecondsMilliseconds() {
        #expect(TranscriptExportService.srtTimestamp(0) == "00:00:00,000")
        #expect(TranscriptExportService.srtTimestamp(1.234) == "00:00:01,234")
        #expect(TranscriptExportService.srtTimestamp(3661.5) == "01:01:01,500")
    }

    @Test func jsonSerializationIncludesSegmentFields() throws {
        let segments = [makeSegment(start: 0.5, end: 2.0, text: "Hi")]
        let json = TranscriptExportService.formatAsTimestampedJSON(segments, plainText: "Hi")
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == 1)
        #expect(decoded?.first?["start"] as? Double == 0.5)
        #expect(decoded?.first?["end"] as? Double == 2.0)
        #expect(decoded?.first?["speaker"] as? String == "Speaker 1")
        #expect(decoded?.first?["text"] as? String == "Hi")
    }

    @Test func serializeWithoutSegmentsFallsBackToTextForSrtAndJson() {
        let source = TranscriptExportService.ExportSource(text: "Fallback body")
        #expect(TranscriptExportService.serialize(source, format: .subtitles) == "Fallback body")
        #expect(TranscriptExportService.serialize(source, format: .timestamps) == "Fallback body")
    }

    @Test func defaultFilenamePrefersSanitizedTitle() {
        let name = TranscriptExportService.defaultFilename(
            title: "Weekly Sync: Q2?",
            timestamp: Date(timeIntervalSince1970: 0),
            format: .markdown
        )
        #expect(name.hasSuffix(".md"))
        #expect(name.contains("Weekly Sync"))
        #expect(!name.contains("?"))
        #expect(!name.contains(":"))
    }

    @Test func defaultFilenameFallsBackToDateWhenTitleMissing() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = TranscriptExportService.defaultFilename(
            title: nil,
            timestamp: date,
            format: .plainText
        )
        #expect(name.hasPrefix("transcript_"))
        #expect(name.hasSuffix(".txt"))
    }
}
