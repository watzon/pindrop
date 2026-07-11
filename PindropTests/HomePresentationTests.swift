//
//  HomePresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-10.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct HomePresentationTests {

    private var en: Locale { Locale(identifier: "en_US") }

    // MARK: - Hero metric formatting

    @Test func wordMetricSingular() {
        #expect(HomePresentation.wordMetric(count: 1, locale: en) == "1 word")
    }

    @Test func wordMetricPluralWithGrouping() {
        let metric = HomePresentation.wordMetric(count: 4210, locale: en)
        #expect(metric == "4,210 words")
    }

    @Test func wordMetricZero() {
        #expect(HomePresentation.wordMetric(count: 0, locale: en) == "0 words")
    }

    @Test func groupedNumberUsesLocaleSeparators() {
        let de = Locale(identifier: "de_DE")
        let formatted = HomePresentation.formatGrouped(4210, locale: de)
        // de_DE uses "." or narrow no-break space depending on OS; must not be bare "4210".
        #expect(formatted != "4210")
        #expect(formatted.contains("4"))
        #expect(formatted.contains("210"))
    }

    @Test func heroSentencePartsSplitAroundMetric() {
        let parts = HomePresentation.heroSentenceParts(wordsThisWeek: 4210, locale: en)
        #expect(parts.before == "You spoke ")
        #expect(parts.metric == "4,210 words")
        #expect(parts.after == " this week.")
    }

    @Test func heroSentencePartsSingularMetric() {
        let parts = HomePresentation.heroSentenceParts(wordsThisWeek: 1, locale: en)
        #expect(parts.metric == "1 word")
        #expect(parts.before == "You spoke ")
        #expect(parts.after == " this week.")
    }

    // MARK: - Streak

    @Test func streakLabelsIncludeZeroAndSingular() {
        #expect(HomePresentation.streakLabel(days: 0, locale: en) == "0-day")
        #expect(HomePresentation.streakLabel(days: 1, locale: en) == "1-day")
        #expect(HomePresentation.streakLabel(days: 14, locale: en) == "14-day")
    }

    // MARK: - Date kicker

    @Test func dateKickerFormatsUppercaseWeekdayAndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 12)))
        let kicker = HomePresentation.dateKicker(date: date, locale: en, calendar: calendar)
        // 2026-07-09 is a Thursday (design artboard used a Wednesday as sample copy only).
        #expect(kicker == "THURSDAY, JULY 9")
    }

    // MARK: - Next midnight

    @Test func nextMidnightIsStartOfFollowingCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let afternoon = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 15, minute: 30))
        )
        let midnight = HomePresentation.nextMidnight(after: afternoon, calendar: calendar)
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 0, minute: 0))
        )
        #expect(midnight == expected)
        #expect(calendar.component(.hour, from: midnight) == 0)
        #expect(calendar.component(.minute, from: midnight) == 0)
    }

    @Test func nextMidnightFromExactlyMidnightAdvancesOneDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 0, minute: 0))
        )
        let next = HomePresentation.nextMidnight(after: midnight, calendar: calendar)
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 0, minute: 0))
        )
        #expect(next == expected)
    }

    @Test func nextMidnightRespectsCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // 2026-07-09 23:30 local → next midnight is 2026-07-10 00:00 local.
        let late = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 23, minute: 30))
        )
        let next = HomePresentation.nextMidnight(after: late, calendar: calendar)
        #expect(calendar.isDate(next, inSameDayAs: try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))
        )))
        #expect(calendar.component(.hour, from: next) == 0)
        #expect(calendar.component(.minute, from: next) == 0)
        #expect(calendar.component(.second, from: next) == 0)
    }

    // MARK: - Sub-line / duration

    @Test func compactDurationFormatsHoursAndMinutes() {
        // 2 h 38 m = 2*3600 + 38*60
        let duration: TimeInterval = 2 * 3600 + 38 * 60
        #expect(HomePresentation.formatCompactDuration(duration, locale: en) == "2 h 38 m")
    }

    @Test func compactDurationHoursOnly() {
        let duration: TimeInterval = 3 * 3600
        #expect(HomePresentation.formatCompactDuration(duration, locale: en) == "3 h")
    }

    @Test func compactDurationMinutesOnly() {
        let duration: TimeInterval = 45 * 60
        #expect(HomePresentation.formatCompactDuration(duration, locale: en) == "45 m")
    }

    @Test func compactDurationZeroIsEmpty() {
        #expect(HomePresentation.formatCompactDuration(0, locale: en).isEmpty)
    }

    @Test func subLineCombinesDictationAndTimeSaved() {
        let spoken: TimeInterval = 2 * 3600 + 38 * 60
        let saved: TimeInterval = 1 * 3600 + 51 * 60
        let line = HomePresentation.subLine(
            dictationDuration: spoken,
            timeSaved: saved,
            locale: en
        )
        #expect(line == "2 h 38 m of dictation — about 1 h 51 m saved over typing it out.")
    }

    @Test func subLineEmptyWhenNoDictation() {
        let line = HomePresentation.subLine(
            dictationDuration: 0,
            timeSaved: 0,
            locale: en
        )
        #expect(line.isEmpty)
    }

    @Test func subLineDurationOnlyWhenNoTimeSaved() {
        let spoken: TimeInterval = 30 * 60
        let line = HomePresentation.subLine(
            dictationDuration: spoken,
            timeSaved: 0,
            locale: en
        )
        #expect(line == "30 m of dictation.")
    }

    // MARK: - Bar height scaling

    @Test func barHeightMaxMapsToFullHeight() {
        let height = HomePresentation.barHeight(words: 100, maxWords: 100, chartHeight: 110, stubHeight: 4)
        #expect(height == 110)
    }

    @Test func barHeightZeroMapsToStub() {
        let height = HomePresentation.barHeight(words: 0, maxWords: 100, chartHeight: 110, stubHeight: 4)
        #expect(height == 4)
    }

    @Test func barHeightZeroMaxMapsToStub() {
        let height = HomePresentation.barHeight(words: 50, maxWords: 0, chartHeight: 110, stubHeight: 4)
        #expect(height == 4)
    }

    @Test func barHeightScalesProportionally() {
        let height = HomePresentation.barHeight(words: 50, maxWords: 100, chartHeight: 110, stubHeight: 4)
        #expect(abs(height - 55) < 0.001)
    }

    @Test func barHeightNeverBelowStubWhenPositive() {
        let height = HomePresentation.barHeight(words: 1, maxWords: 1000, chartHeight: 110, stubHeight: 4)
        #expect(height >= 4)
    }

    // MARK: - Bar day kind / firstWeekday

    @Test func barDayKindRespectsMondayFirstWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday
        // 2026-07-09 is Thursday → index 3 in Mon-first week (Mon=0 … Thu=3)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 12)))
        #expect(HomePresentation.barDayKind(index: 2, now: now, calendar: calendar) == .past)
        #expect(HomePresentation.barDayKind(index: 3, now: now, calendar: calendar) == .today)
        #expect(HomePresentation.barDayKind(index: 4, now: now, calendar: calendar) == .future)
        #expect(HomePresentation.isTodayBarIndex(3, now: now, calendar: calendar))
        #expect(HomePresentation.todayBarIndex(now: now, calendar: calendar) == 3)
    }

    @Test func barDayKindRespectsSundayFirstWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday
        // 2026-07-09 Thursday → index 4 in Sun-first week (Sun=0 … Thu=4)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 12)))
        #expect(HomePresentation.barDayKind(index: 4, now: now, calendar: calendar) == .today)
        #expect(HomePresentation.barDayKind(index: 5, now: now, calendar: calendar) == .future)
        #expect(HomePresentation.todayBarIndex(now: now, calendar: calendar) == 4)
    }

    // MARK: - Accessibility

    @Test func barAccessibilityLabelFormatsWords() {
        #expect(
            HomePresentation.barAccessibilityLabel(weekdayName: "Monday", words: 812, locale: en)
                == "Monday, 812 words"
        )
        #expect(
            HomePresentation.barAccessibilityLabel(weekdayName: "Monday", words: 1, locale: en)
                == "Monday, 1 word"
        )
    }

    // MARK: - WPM display

    @Test func formatWPMRoundsToInteger() {
        #expect(HomePresentation.formatWPM(96.4, locale: en) == "96")
        #expect(HomePresentation.formatWPM(96.6, locale: en) == "97")
        #expect(HomePresentation.formatWPM(0, locale: en) == "0")
    }
}
