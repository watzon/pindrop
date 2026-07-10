//
//  NotesGroupingTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite("NotesGrouping")
struct NotesGroupingTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private var now: Date {
        // Fixed: 2024-06-12 15:00 UTC (Wednesday)
        calendar.date(from: DateComponents(year: 2024, month: 6, day: 12, hour: 15))!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func pinnedSectionComesFirst() {
        let pinnedID = UUID()
        let todayID = UUID()
        let notes = [
            NotesGrouping.Input(id: todayID, updatedAt: now, isPinned: false),
            NotesGrouping.Input(id: pinnedID, updatedAt: date(year: 2024, month: 1, day: 1), isPinned: true),
        ]

        let sections = NotesGrouping.sections(notes: notes, now: now, calendar: calendar)
        #expect(sections.map(\.key) == [.pinned, .today])
        #expect(sections[0].ids == [pinnedID])
        #expect(sections[1].ids == [todayID])
    }

    @Test func groupsTodayYesterdayAndEarlier() {
        let todayID = UUID()
        let yesterdayID = UUID()
        let earlierID = UUID()
        let notes = [
            NotesGrouping.Input(id: earlierID, updatedAt: date(year: 2024, month: 5, day: 1), isPinned: false),
            NotesGrouping.Input(id: todayID, updatedAt: now, isPinned: false),
            NotesGrouping.Input(
                id: yesterdayID,
                updatedAt: date(year: 2024, month: 6, day: 11, hour: 10),
                isPinned: false
            ),
        ]

        let sections = NotesGrouping.sections(notes: notes, now: now, calendar: calendar)
        #expect(sections.count == 3)
        #expect(sections[0].key == .today)
        #expect(sections[0].ids == [todayID])
        #expect(sections[1].key == .yesterday)
        #expect(sections[1].ids == [yesterdayID])
        if case .day(let day) = sections[2].key {
            #expect(calendar.isDate(day, inSameDayAs: date(year: 2024, month: 5, day: 1)))
            #expect(sections[2].ids == [earlierID])
        } else {
            Issue.record("Expected earlier day section")
        }
    }

    @Test func sortsWithinSectionByUpdatedAtDescending() {
        let older = UUID()
        let newer = UUID()
        let notes = [
            NotesGrouping.Input(id: older, updatedAt: date(year: 2024, month: 6, day: 12, hour: 9), isPinned: false),
            NotesGrouping.Input(id: newer, updatedAt: date(year: 2024, month: 6, day: 12, hour: 18), isPinned: false),
        ]

        let sections = NotesGrouping.sections(notes: notes, now: now, calendar: calendar)
        #expect(sections.count == 1)
        #expect(sections[0].ids == [newer, older])
    }

    @Test func emptyInputReturnsNoSections() {
        #expect(NotesGrouping.sections(notes: [], now: now, calendar: calendar).isEmpty)
    }

    @Test func localizationKeysForStableSections() {
        #expect(NotesGrouping.SectionKey.pinned.localizationKey == "Pinned")
        #expect(NotesGrouping.SectionKey.today.localizationKey == "Today")
        #expect(NotesGrouping.SectionKey.yesterday.localizationKey == "Yesterday")
    }
}
