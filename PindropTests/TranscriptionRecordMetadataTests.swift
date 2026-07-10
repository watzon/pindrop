//
//  TranscriptionRecordMetadataTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct TranscriptionRecordMetadataTests {

    private func makeRecord(
        diarizationJSON: String? = nil,
        aiSummary: String? = nil,
        text: String = "hello"
    ) -> TranscriptionRecord {
        TranscriptionRecord(
            text: text,
            duration: 1.0,
            modelUsed: "base",
            diarizationSegmentsJSON: diarizationJSON,
            aiSummary: aiSummary
        )
    }

    private func segmentsJSON(_ segments: [DiarizedTranscriptSegment]) throws -> String {
        let data = try JSONEncoder().encode(segments)
        return try #require(String(data: data, encoding: .utf8))
    }

    @Test func speakerCountIsZeroWithoutDiarization() {
        let record = makeRecord()
        #expect(record.speakerCount == 0)
        #expect(!record.isDiarized)
        #expect(!record.hasSummary)
    }

    @Test func speakerCountCountsDistinctSpeakerIds() throws {
        let segments = [
            DiarizedTranscriptSegment(
                speakerId: "s1",
                speakerLabel: "Alice",
                startTime: 0,
                endTime: 1,
                confidence: 1,
                text: "Hi"
            ),
            DiarizedTranscriptSegment(
                speakerId: "s2",
                speakerLabel: "Bob",
                startTime: 1,
                endTime: 2,
                confidence: 1,
                text: "Hello"
            ),
            DiarizedTranscriptSegment(
                speakerId: "s1",
                speakerLabel: "Alice",
                startTime: 2,
                endTime: 3,
                confidence: 1,
                text: "Again"
            )
        ]
        let record = makeRecord(diarizationJSON: try segmentsJSON(segments))
        #expect(record.speakerCount == 2)
        #expect(record.isDiarized)
    }

    @Test func hasSummaryRequiresNonEmptyText() {
        #expect(!makeRecord(aiSummary: nil).hasSummary)
        #expect(!makeRecord(aiSummary: "   ").hasSummary)
        #expect(makeRecord(aiSummary: "Roadmap risks").hasSummary)
    }

    @Test func meetingMetadataStringComposesLocalizedParts() throws {
        let segments = [
            DiarizedTranscriptSegment(
                speakerId: "a",
                speakerLabel: "A",
                startTime: 0,
                endTime: 1,
                confidence: 1,
                text: "one"
            ),
            DiarizedTranscriptSegment(
                speakerId: "b",
                speakerLabel: "B",
                startTime: 1,
                endTime: 2,
                confidence: 1,
                text: "two"
            ),
            DiarizedTranscriptSegment(
                speakerId: "c",
                speakerLabel: "C",
                startTime: 2,
                endTime: 3,
                confidence: 1,
                text: "three"
            )
        ]
        let record = makeRecord(
            diarizationJSON: try segmentsJSON(segments),
            aiSummary: "Summary of the call"
        )
        let locale = Locale(identifier: "en")
        let metadata = record.meetingMetadataString(locale: locale)

        #expect(metadata.contains("3 speakers") || metadata.contains("speakers"))
        #expect(metadata.contains("diarized"))
        #expect(metadata.contains("summary ready"))
        #expect(metadata.contains("·"))
    }

    @Test func meetingMetadataStringIsEmptyWhenNoSignals() {
        let record = makeRecord()
        #expect(record.meetingMetadataString(locale: Locale(identifier: "en")).isEmpty)
    }

    @Test func singleSpeakerUsesSingularForm() throws {
        let segments = [
            DiarizedTranscriptSegment(
                speakerId: "solo",
                speakerLabel: "Only",
                startTime: 0,
                endTime: 1,
                confidence: 1,
                text: "hi"
            )
        ]
        let record = makeRecord(diarizationJSON: try segmentsJSON(segments))
        let metadata = record.meetingMetadataString(locale: Locale(identifier: "en"))
        #expect(metadata.contains("1 speaker") || metadata.contains("speaker"))
        #expect(!metadata.contains("1 speakers"))
    }
}
