//
//  HomePresentation.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Pure helpers for Home (Dashboard) presentation (U4). No SwiftUI / SwiftData side effects.
//

import CoreGraphics
import Foundation

// MARK: - Layout metrics (spec §9 — normative)

enum HomeLayoutMetrics {
    /// Hero sentence: Newsreader 46/52 · -0.02em
    static let heroFontSize: CGFloat = 46
    static let heroLineHeight: CGFloat = 52
    static let heroTrackingEm: CGFloat = -0.02
    static let heroBottomPadding: CGFloat = 10

    /// Stats strip
    static let statsTopPadding: CGFloat = 36
    static let statsBottomPadding: CGFloat = 40
    static let statsDividerHeight: CGFloat = 40
    static let statsDividerWidth: CGFloat = 1
    static let statsGroupPadding: CGFloat = 32
    static let statsInnerGap: CGFloat = 4
    static let statsNumberSize: CGFloat = 22
    static let statsNumberLineHeight: CGFloat = 28
    static let statsLabelSize: CGFloat = 11
    static let statsLabelTrackingEm: CGFloat = 0.07

    /// Date kicker
    static let kickerSize: CGFloat = 11
    static let kickerTrackingEm: CGFloat = 0.08

    /// THIS WEEK chart
    static let chartTopPadding: CGFloat = 40
    static let chartSectionGap: CGFloat = 14
    static let chartBarAreaHeight: CGFloat = 110
    static let chartBarWidth: CGFloat = 30
    static let chartBarGap: CGFloat = 28
    static let chartBarTopRadius: CGFloat = 5
    static let chartBarBottomRadius: CGFloat = 2
    static let chartStubHeight: CGFloat = 4
    static let chartLabelGap: CGFloat = 8
    static let weekTotalBottomPadding: CGFloat = 24
}

// MARK: - Presentation helpers

enum HomePresentation {
    // MARK: Number / metric formatting

    /// Locale-aware grouping separators ("4,210" / "4.210").
    static func formatGrouped(_ number: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// "1 word" or "4,210 words" (grouped count for plural).
    static func wordMetric(count: Int, locale: Locale) -> String {
        if count == 1 {
            return localized("1 word", locale: locale)
        }
        return String(
            format: localized("%@ words", locale: locale),
            formatGrouped(count, locale: locale)
        )
    }

    /// Integer WPM for the stats strip ("96").
    static func formatWPM(_ wpm: Double, locale: Locale) -> String {
        let rounded = Int(wpm.rounded())
        return formatGrouped(rounded, locale: locale)
    }

    /// Streak label: "0-day", "1-day", "14-day".
    static func streakLabel(days: Int, locale: Locale) -> String {
        if days == 0 {
            return localized("0-day", locale: locale)
        }
        if days == 1 {
            return localized("1-day", locale: locale)
        }
        return String(format: localized("%d-day", locale: locale), days)
    }

    // MARK: Day boundary

    /// Start of the next calendar day after `date` (local midnight).
    /// Used to schedule Home re-renders so WORDS TODAY / STREAK / kicker / today-bar
    /// do not stay frozen when the window is left open overnight.
    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        if let next = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
            return next
        }
        // Extremely defensive fallback (calendar arithmetic should not fail for gregorian).
        return date.addingTimeInterval(24 * 60 * 60)
    }

    // MARK: Date kicker

    /// Uppercase weekday + date, e.g. "WEDNESDAY, JULY 9".
    static func dateKicker(
        date: Date,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
        return formatter.string(from: date).uppercased(with: locale)
    }

    // MARK: Hero sentence

    /// Segments of the localized hero sentence so the metric can be styled independently.
    /// Template is "You spoke %@ this week." — the metric placeholder may appear at any index.
    struct HeroSentenceParts: Equatable {
        let before: String
        let metric: String
        let after: String
    }

    static func heroSentenceParts(wordsThisWeek: Int, locale: Locale) -> HeroSentenceParts {
        let metric = wordMetric(count: wordsThisWeek, locale: locale)
        let template = localized("You spoke %@ this week.", locale: locale)
        if let range = template.range(of: "%@") {
            return HeroSentenceParts(
                before: String(template[..<range.lowerBound]),
                metric: metric,
                after: String(template[range.upperBound...])
            )
        }
        // Fallback if a locale omits the placeholder.
        return HeroSentenceParts(before: template, metric: metric, after: "")
    }

    // MARK: Sub-line (duration + time saved)

    /// Formats a duration as "2 h 38 m" / "2 h" / "38 m" / empty when zero.
    static func formatCompactDuration(_ duration: TimeInterval, locale: Locale) -> String {
        guard duration.isFinite, duration > 0 else { return "" }
        let totalMinutes = Int(duration.rounded(.down)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return String(
                format: localized("%d h %d m", locale: locale),
                hours,
                minutes
            )
        }
        if hours > 0 {
            return String(format: localized("%d h", locale: locale), hours)
        }
        // Prefer at least 1 m when there is positive duration under a minute.
        return String(format: localized("%d m", locale: locale), max(1, minutes))
    }

    /// "2 h 38 m of dictation — about 1 h 51 m saved over typing it out."
    /// Empty-week: quiet empty string so the view can hide the sub-line or show a short empty hint.
    static func subLine(
        dictationDuration: TimeInterval,
        timeSaved: TimeInterval,
        locale: Locale
    ) -> String {
        let spoken = formatCompactDuration(dictationDuration, locale: locale)
        guard !spoken.isEmpty else { return "" }

        let saved = formatCompactDuration(timeSaved, locale: locale)
        if saved.isEmpty {
            return String(
                format: localized("%@ of dictation.", locale: locale),
                spoken
            )
        }
        return String(
            format: localized("%@ of dictation — about %@ saved over typing it out.", locale: locale),
            spoken,
            saved
        )
    }

    // MARK: Bar chart math

    /// Maps a weekday word count to bar height. Max bucket → full chart height; zero → stub.
    static func barHeight(
        words: Int,
        maxWords: Int,
        chartHeight: CGFloat = HomeLayoutMetrics.chartBarAreaHeight,
        stubHeight: CGFloat = HomeLayoutMetrics.chartStubHeight
    ) -> CGFloat {
        guard words > 0, maxWords > 0, chartHeight > 0 else {
            return stubHeight
        }
        let ratio = CGFloat(words) / CGFloat(maxWords)
        return max(stubHeight, ratio * chartHeight)
    }

    /// Whether the bar index is "today" within the calendar week ordered by `firstWeekday`.
    static func isTodayBarIndex(
        _ index: Int,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        let todayIndex = (weekday - calendar.firstWeekday + 7) % 7
        return index == todayIndex
    }

    /// Past / today / future relative to `now` for a bar index in the firstWeekday-ordered week.
    enum BarDayKind: Equatable {
        case past
        case today
        case future
    }

    static func barDayKind(
        index: Int,
        now: Date,
        calendar: Calendar
    ) -> BarDayKind {
        let weekday = calendar.component(.weekday, from: now)
        let todayIndex = (weekday - calendar.firstWeekday + 7) % 7
        if index < todayIndex { return .past }
        if index == todayIndex { return .today }
        return .future
    }

    /// Short weekday labels ordered from `calendar.firstWeekday` (locale-aware).
    static func weekdayLabels(calendar: Calendar, locale: Locale) -> [String] {
        var cal = calendar
        cal.locale = locale
        let symbols = cal.veryShortWeekdaySymbols
        guard symbols.count == 7 else {
            return symbols
        }
        let first = cal.firstWeekday - 1 // 0-based into Sunday-first array
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    /// Full weekday names ordered from `calendar.firstWeekday` (for a11y).
    static func weekdayNames(calendar: Calendar, locale: Locale) -> [String] {
        var cal = calendar
        cal.locale = locale
        let symbols = cal.weekdaySymbols
        guard symbols.count == 7 else {
            return symbols
        }
        let first = cal.firstWeekday - 1
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    /// Accessibility label: "Monday, 812 words".
    static func barAccessibilityLabel(
        weekdayName: String,
        words: Int,
        locale: Locale
    ) -> String {
        if words == 1 {
            return String(
                format: localized("%@, 1 word", locale: locale),
                weekdayName
            )
        }
        return String(
            format: localized("%@, %@ words", locale: locale),
            weekdayName,
            formatGrouped(words, locale: locale)
        )
    }
}
