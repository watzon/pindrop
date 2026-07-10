//
//  LibraryPresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct LibraryPresentationTests {

    // MARK: - Filter mapping

    @Test func filterChipsMapToExpectedSourceKinds() {
        #expect(LibraryFilterChip.all.sourceKinds == nil)
        #expect(LibraryFilterChip.dictations.sourceKinds == [.voiceRecording])
        #expect(LibraryFilterChip.meetings.sourceKinds == [.manualCapture])
        #expect(LibraryFilterChip.media.sourceKinds == [.importedFile, .webLink])
    }

    @Test func filterChipsMapToHistoryFiltersAndBack() {
        #expect(LibraryFilterChip.all.historyFilter == .all)
        #expect(LibraryFilterChip.dictations.historyFilter == .voice)
        #expect(LibraryFilterChip.meetings.historyFilter == .meetings)
        #expect(LibraryFilterChip.media.historyFilter == .media)

        #expect(LibraryFilterChip.from(historyFilter: .all) == .all)
        #expect(LibraryFilterChip.from(historyFilter: .voice) == .dictations)
        #expect(LibraryFilterChip.from(historyFilter: .meetings) == .meetings)
        #expect(LibraryFilterChip.from(historyFilter: .media) == .media)
    }

    @Test func filterIncludesMatchesSourceKinds() {
        #expect(LibraryFilterChip.all.includes(.voiceRecording))
        #expect(LibraryFilterChip.all.includes(.webLink))
        #expect(LibraryFilterChip.dictations.includes(.voiceRecording))
        #expect(!LibraryFilterChip.dictations.includes(.manualCapture))
        #expect(LibraryFilterChip.media.includes(.importedFile))
        #expect(LibraryFilterChip.media.includes(.webLink))
        #expect(!LibraryFilterChip.media.includes(.voiceRecording))
        #expect(LibraryFilterChip.meetings.includes(.manualCapture))
        #expect(!LibraryFilterChip.meetings.includes(.importedFile))
    }

    // MARK: - Retention caption

    @Test func retentionCaptionFormatsPolicy() {
        let locale = Locale(identifier: "en")
        #expect(
            LibraryRetentionCaption.caption(
                retention: .days7,
                hasAudio: true,
                sourceKind: .voiceRecording,
                locale: locale
            ) == "audio kept 7 days"
        )
        #expect(
            LibraryRetentionCaption.caption(
                retention: .days30,
                hasAudio: true,
                sourceKind: .voiceRecording,
                locale: locale
            ) == "audio kept 30 days"
        )
        #expect(
            LibraryRetentionCaption.caption(
                retention: .forever,
                hasAudio: true,
                sourceKind: .voiceRecording,
                locale: locale
            ) == "audio kept forever"
        )
        #expect(
            LibraryRetentionCaption.caption(
                retention: .off,
                hasAudio: true,
                sourceKind: .voiceRecording,
                locale: locale
            ) == nil
        )
        #expect(
            LibraryRetentionCaption.caption(
                retention: .days7,
                hasAudio: false,
                sourceKind: .voiceRecording,
                locale: locale
            ) == nil
        )
        #expect(
            LibraryRetentionCaption.caption(
                retention: .days7,
                hasAudio: true,
                sourceKind: .manualCapture,
                locale: locale
            ) == nil
        )
    }

    // MARK: - Speaker colors

    @Test func speakerColorIsStableForSameID() {
        let a = LibrarySpeakerColor.index(for: "speaker-alice")
        let b = LibrarySpeakerColor.index(for: "speaker-alice")
        #expect(a == b)
        #expect(LibrarySpeakerColor.color(for: "speaker-alice") == LibrarySpeakerColor.color(for: "speaker-alice"))
    }

    @Test func speakerPaletteHasAtLeastSixDistinctColors() {
        #expect(LibrarySpeakerColor.palette.count >= 6)
        // Distinct hex-ish values via description uniqueness.
        let descriptions = Set(LibrarySpeakerColor.palette.map { "\($0)" })
        #expect(descriptions.count >= 6)
    }

    @Test func speakerIndexesSpreadAcrossPalette() {
        let ids = (0..<32).map { "speaker-\($0)" }
        let indexes = Set(ids.map { LibrarySpeakerColor.index(for: $0) })
        #expect(indexes.count >= 6)
    }

    // MARK: - Day grouping

    @Test func dayGroupingBuildsTodayYesterdayAndDateSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 15)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let older = try #require(calendar.date(byAdding: .day, value: -5, to: now))

        let records = [
            TranscriptionRecord(text: "today", timestamp: now, duration: 1, modelUsed: "base"),
            TranscriptionRecord(text: "yesterday", timestamp: yesterday, duration: 1, modelUsed: "base"),
            TranscriptionRecord(text: "older", timestamp: older, duration: 1, modelUsed: "base"),
        ]

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let sections = LibraryDayGrouping.sections(
            from: records,
            calendar: calendar,
            now: now,
            newestFirst: true,
            dateFormatter: formatter
        )

        #expect(sections.map(\.key) == [
            "Today",
            "Yesterday",
            formatter.string(from: older)
        ])
        #expect(sections[0].records.first?.text == "today")
        #expect(sections[1].records.first?.text == "yesterday")
        #expect(sections[2].records.first?.text == "older")
    }

    // MARK: - Header meta / rates

    @Test func headerMetaFormatsCountAndSpokenDuration() {
        let locale = Locale(identifier: "en")
        let text = LibraryHeaderMeta.text(
            recordingCount: 12,
            spokenDuration: 2 * 3600 + 15 * 60,
            locale: locale
        )
        #expect(text.contains("12 recordings"))
        #expect(text.contains("2 h 15 m spoken"))
    }

    @Test func playbackRateCyclesThroughSpecValues() {
        #expect(LibraryPlaybackRate.next(after: 1.0) == 1.5)
        #expect(LibraryPlaybackRate.next(after: 1.5) == 2.0)
        #expect(LibraryPlaybackRate.next(after: 2.0) == 1.0)
        #expect(LibraryPlaybackRate.label(for: 1.0) == "1×")
        #expect(LibraryPlaybackRate.label(for: 1.5) == "1.5×")
        #expect(LibraryPlaybackRate.label(for: 2.0) == "2×")
    }
}
