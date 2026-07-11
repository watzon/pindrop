//
//  DashboardStatsServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct DashboardStatsServiceTests {

    // MARK: - Fixtures

    private let fixedNow: Date = {
        // Wednesday 2024-06-12 15:30:00 America/Los_Angeles
        Self.date(year: 2024, month: 6, day: 12, hour: 15, minute: 30)
    }()

    private func makeCalendar(firstWeekday: Int = 1, timeZoneIdentifier: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0,
        timeZoneIdentifier: String = "America/Los_Angeles"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return calendar.date(from: components)!
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        Self.date(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    private func sample(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        wordCount: Int = 10,
        duration: TimeInterval = 60
    ) -> StatsSample {
        StatsSample(
            timestamp: date(year: year, month: month, day: day, hour: hour, minute: minute),
            wordCount: wordCount,
            duration: duration
        )
    }

    // MARK: - Today / week boundaries

    @Test func todayBoundary_recordAt2359YesterdayExcludedFromToday() {
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2024, month: 6, day: 11, hour: 23, minute: 59, wordCount: 5, duration: 30),
            sample(year: 2024, month: 6, day: 12, hour: 0, minute: 1, wordCount: 7, duration: 40),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsToday == 7)
        #expect(sut.sessionsToday == 1)
        #expect(sut.wordsThisWeek == 12)
        #expect(sut.sessionsThisWeek == 2)
    }

    @Test func todayBoundary_recordAt0001TodayIncluded() {
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2024, month: 6, day: 12, hour: 0, minute: 1, wordCount: 20, duration: 50),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsToday == 20)
        #expect(sut.sessionsToday == 1)
        #expect(sut.sessionsThisWeek == 1)
    }

    // MARK: - Week straddling month / year

    @Test func weekStraddlingMonthBoundary() {
        // Week of Sun 2024-06-30 … Sat 2024-07-06 with firstWeekday = Sunday.
        // "now" is Wednesday 2024-07-03.
        let now = date(year: 2024, month: 7, day: 3, hour: 10)
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2024, month: 6, day: 30, wordCount: 3, duration: 10), // Sunday prior month
            sample(year: 2024, month: 7, day: 1, wordCount: 4, duration: 10),
            sample(year: 2024, month: 7, day: 3, wordCount: 5, duration: 10),
            sample(year: 2024, month: 6, day: 29, wordCount: 100, duration: 10), // prior week — excluded
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: now)

        #expect(sut.wordsThisWeek == 12)
        #expect(sut.sessionsThisWeek == 3)
        #expect(sut.wordsToday == 5)
    }

    @Test func weekStraddlingYearBoundary() {
        // Week of Sun 2023-12-31 … Sat 2024-01-06 with firstWeekday = Sunday.
        let now = date(year: 2024, month: 1, day: 3, hour: 14)
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2023, month: 12, day: 31, wordCount: 8, duration: 20),
            sample(year: 2024, month: 1, day: 2, wordCount: 12, duration: 30),
            sample(year: 2023, month: 12, day: 30, wordCount: 50, duration: 10), // prior week
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: now)

        #expect(sut.wordsThisWeek == 20)
        #expect(sut.sessionsThisWeek == 2)
        #expect(sut.dictationDurationThisWeek == 50)
    }

    // MARK: - Streak

    @Test func streak_activeToday() {
        let calendar = makeCalendar()
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 1), // today
            sample(year: 2024, month: 6, day: 11, wordCount: 1),
            sample(year: 2024, month: 6, day: 10, wordCount: 1),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.streakDays == 3)
    }

    @Test func streak_gapTodayButActiveYesterday() {
        let calendar = makeCalendar()
        let samples = [
            sample(year: 2024, month: 6, day: 11, wordCount: 1), // yesterday
            sample(year: 2024, month: 6, day: 10, wordCount: 1),
            sample(year: 2024, month: 6, day: 9, wordCount: 1),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.streakDays == 3)
    }

    @Test func streak_brokenWhenGapYesterdayAndTodayEmpty() {
        let calendar = makeCalendar()
        let samples = [
            sample(year: 2024, month: 6, day: 10, wordCount: 1), // two days ago — streak broken
            sample(year: 2024, month: 6, day: 9, wordCount: 1),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.streakDays == 0)
    }

    @Test func streak_emptySamplesIsZero() {
        let calendar = makeCalendar()
        let sut = DashboardStatsService.compute(samples: [], calendar: calendar, now: fixedNow)
        #expect(sut.streakDays == 0)
        #expect(sut == .empty)
    }

    @Test func streak_stopsAtGapEvenWhenTodayActive() {
        let calendar = makeCalendar()
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 1), // today
            // gap on day 11
            sample(year: 2024, month: 6, day: 10, wordCount: 1),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.streakDays == 1)
    }

    // MARK: - DST transitions (America/Los_Angeles)

    @Test func dstSpringForward_streakAndWeekdayBucketsHoldAcross23HourDay() {
        // 2024-03-10: US spring-forward (02:00 → 03:00 PT). Calendar day is 23 hours; Sunday.
        // "now" is later the same day, after the jump. firstWeekday = Sunday so the week is Mar 10–16.
        let calendar = makeCalendar(firstWeekday: 1)
        let now = date(year: 2024, month: 3, day: 10, hour: 10, minute: 0)
        let samples = [
            sample(year: 2024, month: 3, day: 8, hour: 12, wordCount: 1), // Fri — streak
            sample(year: 2024, month: 3, day: 9, hour: 23, minute: 30, wordCount: 2), // Sat prior week
            sample(year: 2024, month: 3, day: 10, hour: 1, minute: 30, wordCount: 3), // before jump (PST)
            sample(year: 2024, month: 3, day: 10, hour: 3, minute: 30, wordCount: 4), // after jump (PDT)
            sample(year: 2024, month: 3, day: 11, hour: 9, wordCount: 5), // Mon — same week
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: now)

        // Calendar-day streak walks Mar 10 → 9 → 8 despite the 23h wall-clock day.
        #expect(sut.streakDays == 3)
        // Both pre- and post-transition samples on Mar 10 count as the same weekday bucket.
        #expect(sut.wordsToday == 7)
        #expect(sut.sessionsToday == 2)
        #expect(sut.wordsThisWeek == 12) // Mar 10 (7) + Mar 11 (5); Mar 9 is prior week
        #expect(sut.wordsPerWeekday == [7, 5, 0, 0, 0, 0, 0]) // Sun, Mon
    }

    @Test func dstFallBack_streakAndWeekdayBucketsHoldAcross25HourDay() {
        // 2024-11-03: US fall-back (02:00 → 01:00 PT). Calendar day is 25 hours; Sunday.
        // "now" is afternoon of the transition day. Week with firstWeekday Sunday: Nov 3–9.
        let calendar = makeCalendar(firstWeekday: 1)
        let now = date(year: 2024, month: 11, day: 3, hour: 15, minute: 0)
        let samples = [
            sample(year: 2024, month: 11, day: 1, hour: 12, wordCount: 1), // Fri — streak
            sample(year: 2024, month: 11, day: 2, hour: 18, wordCount: 2), // Sat prior week for buckets
            // Unambiguous local times on the 25h day (avoid the repeated 01:00–02:00 hour).
            sample(year: 2024, month: 11, day: 3, hour: 0, minute: 30, wordCount: 3), // early morning PDT
            sample(year: 2024, month: 11, day: 3, hour: 14, minute: 0, wordCount: 4), // afternoon PST
            sample(year: 2024, month: 11, day: 4, hour: 10, wordCount: 6), // Mon — same week
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: now)

        // Streak still counts calendar days Nov 3 → 2 → 1 across the 25h wall-clock day.
        #expect(sut.streakDays == 3)
        #expect(sut.wordsToday == 7)
        #expect(sut.sessionsToday == 2)
        #expect(sut.wordsThisWeek == 13) // Nov 3 (7) + Nov 4 (6); Nov 2 is prior week
        #expect(sut.wordsPerWeekday == [7, 6, 0, 0, 0, 0, 0]) // Sun, Mon
    }

    // MARK: - firstWeekday / wordsPerWeekday

    @Test func wordsPerWeekday_sundayFirstWeekday() {
        // fixedNow = Wed 2024-06-12. Week Sun 6/9 … Sat 6/15 when firstWeekday = 1.
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2024, month: 6, day: 9, wordCount: 1),  // Sun → index 0
            sample(year: 2024, month: 6, day: 10, wordCount: 2), // Mon → index 1
            sample(year: 2024, month: 6, day: 12, wordCount: 4), // Wed → index 3
            sample(year: 2024, month: 6, day: 15, wordCount: 8), // Sat → index 6
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsPerWeekday == [1, 2, 0, 4, 0, 0, 8])
    }

    @Test func wordsPerWeekday_mondayFirstWeekday() {
        // Week Mon 6/10 … Sun 6/16 when firstWeekday = 2.
        let calendar = makeCalendar(firstWeekday: 2)
        let samples = [
            sample(year: 2024, month: 6, day: 10, wordCount: 1), // Mon → index 0
            sample(year: 2024, month: 6, day: 12, wordCount: 3), // Wed → index 2
            sample(year: 2024, month: 6, day: 16, wordCount: 5), // Sun → index 6
            sample(year: 2024, month: 6, day: 9, wordCount: 99), // Sun prior week — excluded
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsPerWeekday == [1, 0, 3, 0, 0, 0, 5])
        #expect(sut.wordsThisWeek == 9)
    }

    @Test func activityWords_coverRolling365DaysEndingToday() {
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2023, month: 6, day: 14, wordCount: 3), // first day in range
            sample(year: 2023, month: 6, day: 15, wordCount: 4),
            sample(year: 2024, month: 6, day: 12, wordCount: 5),
            sample(year: 2023, month: 6, day: 13, wordCount: 99), // outside range
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsPerActivityDay.count == 365)
        #expect(sut.wordsPerActivityDay[0] == 3)
        #expect(sut.wordsPerActivityDay[1] == 4)
        #expect(sut.wordsPerActivityDay[364] == 5)
        #expect(sut.wordsPerActivityDay.reduce(0, +) == 12)
    }

    @Test func activityWords_emptySamplesProvideEmptyGrid() {
        let calendar = makeCalendar()
        let sut = DashboardStatsService.compute(samples: [], calendar: calendar, now: fixedNow)

        #expect(sut.wordsPerActivityDay == Array(repeating: 0, count: 365))
    }

    @Test func activityIntensity_usesFourNonzeroLevels() {
        #expect(HomePresentation.activityIntensity(words: 0, maxWords: 100) == 0)
        #expect(HomePresentation.activityIntensity(words: 1, maxWords: 100) == 1)
        #expect(HomePresentation.activityIntensity(words: 25, maxWords: 100) == 1)
        #expect(HomePresentation.activityIntensity(words: 26, maxWords: 100) == 2)
        #expect(HomePresentation.activityIntensity(words: 75, maxWords: 100) == 3)
        #expect(HomePresentation.activityIntensity(words: 100, maxWords: 100) == 4)
    }

    // MARK: - WPM safety

    @Test func wpmThisWeek_zeroDurationIsSafe() {
        let calendar = makeCalendar()
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 100, duration: 0),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wpmThisWeek == 0)
        #expect(sut.wordsThisWeek == 100)
        #expect(sut.dictationDurationThisWeek == 0)
    }

    @Test func wpmThisWeek_dividesWordsByMinutes() {
        let calendar = makeCalendar()
        // 120 words in 60 seconds → 120 WPM
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 120, duration: 60),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wpmThisWeek == 120)
    }

    // MARK: - Time saved

    @Test func timeSavedThisWeek_floorsAtZero() {
        let calendar = makeCalendar()
        // 10 words at 40 WPM = 15s typing; 120s dictation → time saved floors at 0
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 10, duration: 120),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.timeSavedThisWeek == 0)
    }

    @Test func timeSavedThisWeek_positiveWhenDictationFasterThanTyping() {
        let calendar = makeCalendar()
        // 40 words at 40 WPM = 60s typing; 20s dictation → 40s saved
        let samples = [
            sample(year: 2024, month: 6, day: 12, wordCount: 40, duration: 20),
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.timeSavedThisWeek == 40)
    }

    // MARK: - Sample from text / mapper shape

    @Test func statsSample_countsWordsFromText() {
        let sample = StatsSample(
            timestamp: fixedNow,
            text: "hello world\nfoo  bar",
            duration: 5
        )
        #expect(sample.wordCount == 4)
    }

    @Test func emptyWeekOutsideRangeExcluded() {
        let calendar = makeCalendar(firstWeekday: 1)
        let samples = [
            sample(year: 2024, month: 6, day: 8, wordCount: 50, duration: 30), // Saturday prior week
        ]

        let sut = DashboardStatsService.compute(samples: samples, calendar: calendar, now: fixedNow)

        #expect(sut.wordsThisWeek == 0)
        #expect(sut.sessionsThisWeek == 0)
        #expect(sut.dictationDurationThisWeek == 0)
        #expect(sut.wordsPerWeekday == Array(repeating: 0, count: 7))
    }
}
