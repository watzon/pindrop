//
//  StatsPresentation.swift
//  Pindrop
//
//  Created on 2026-07-11.
//
//  Pure aggregation and presentation helpers for the Stats page.
//

import Foundation

enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear
    case allTime

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .sevenDays: return localized("7 days", locale: locale)
        case .thirtyDays: return localized("30 days", locale: locale)
        case .ninetyDays: return localized("90 days", locale: locale)
        case .oneYear: return localized("1 year", locale: locale)
        case .allTime: return localized("All time", locale: locale)
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let days: Int?
        switch self {
        case .sevenDays: days = 6
        case .thirtyDays: days = 29
        case .ninetyDays: days = 89
        case .oneYear: days = 364
        case .allTime: days = nil
        }
        return days.flatMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

enum StatsMetric: String, CaseIterable, Identifiable, Sendable {
    case words
    case sessions
    case duration

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .words: return localized("Words", locale: locale)
        case .sessions: return localized("Sessions", locale: locale)
        case .duration: return localized("Duration", locale: locale)
        }
    }
}

struct StatsRecord: Equatable, Sendable {
    let timestamp: Date
    let words: Int
    let duration: TimeInterval
    let sourceKind: MediaSourceKind
    let destinationApp: String?
    let isEnhanced: Bool
    /// Pipeline latencies from instrumented dictations; nil for media imports
    /// and records that predate metrics capture.
    let transcriptionSeconds: Double?
    let enhancementSeconds: Double?
    let totalPipelineSeconds: Double?

    init(
        timestamp: Date,
        words: Int,
        duration: TimeInterval,
        sourceKind: MediaSourceKind,
        destinationApp: String?,
        isEnhanced: Bool,
        transcriptionSeconds: Double? = nil,
        enhancementSeconds: Double? = nil,
        totalPipelineSeconds: Double? = nil
    ) {
        self.timestamp = timestamp
        self.words = words
        self.duration = duration
        self.sourceKind = sourceKind
        self.destinationApp = destinationApp
        self.isEnhanced = isEnhanced
        self.transcriptionSeconds = transcriptionSeconds
        self.enhancementSeconds = enhancementSeconds
        self.totalPipelineSeconds = totalPipelineSeconds
    }
}

struct StatsBucket: Identifiable, Equatable, Sendable {
    let startDate: Date
    let words: Int
    let sessions: Int
    let duration: TimeInterval
    var id: Date { startDate }
}

struct StatsCategoryBucket: Identifiable, Equatable, Sendable {
    let id: String
    let words: Int
    let sessions: Int
    let duration: TimeInterval
}

struct StatsSnapshot: Equatable, Sendable {
    let totalWords: Int
    let totalSessions: Int
    let totalDuration: TimeInterval
    let activeDays: Int
    let averageWordsPerSession: Double
    let averageSessionDuration: TimeInterval
    let longestStreak: Int
    let enhancedSessions: Int
    let estimatedTimeSaved: TimeInterval
    let averageWPM: Double
    /// Averages over dictations that captured pipeline metrics; 0 when none did.
    let averageTranscriptionSeconds: Double
    let averageEnhancementSeconds: Double
    let averageTotalPipelineSeconds: Double
    let activity: [StatsBucket]
    let weekdays: [StatsCategoryBucket]
    let hours: [StatsCategoryBucket]
    let sources: [StatsCategoryBucket]
    let destinations: [StatsCategoryBucket]

    static let empty = StatsSnapshot(
        totalWords: 0, totalSessions: 0, totalDuration: 0, activeDays: 0,
        averageWordsPerSession: 0, averageSessionDuration: 0, longestStreak: 0,
        enhancedSessions: 0, estimatedTimeSaved: 0, averageWPM: 0,
        averageTranscriptionSeconds: 0, averageEnhancementSeconds: 0,
        averageTotalPipelineSeconds: 0,
        activity: [], weekdays: [], hours: [], sources: [], destinations: []
    )
}

enum StatsService {
    /// Lightweight Sendable projection of SwiftData models for aggregation.
    /// Keeps managed models off any background isolation boundary.
    static func project(_ records: [TranscriptionRecord]) -> [StatsRecord] {
        records.map(record(from:))
    }

    static func record(from record: TranscriptionRecord) -> StatsRecord {
        let metrics = record.pipelineMetrics
        return StatsRecord(
            timestamp: record.timestamp,
            words: max(0, record.effectiveWordCount),
            duration: normalizedDuration(record.duration),
            sourceKind: record.resolvedSourceKind,
            destinationApp: normalizedName(record.destinationAppName),
            isEnhanced: record.enhancedWith != nil,
            transcriptionSeconds: metrics?.transcriptionSeconds,
            enhancementSeconds: metrics?.enhancementSeconds,
            totalPipelineSeconds: metrics?.totalSeconds
        )
    }

    static func compute(
        records: [StatsRecord],
        range: StatsRange,
        calendar: Calendar,
        now: Date
    ) -> StatsSnapshot {
        let start = range.startDate(now: now, calendar: calendar)
        let filtered = records.filter { record in
            record.timestamp <= now && (start.map { record.timestamp >= $0 } ?? true)
        }
        guard !filtered.isEmpty else { return .empty }

        let totalWords = filtered.reduce(0) { $0 + $1.words }
        let totalDuration = filtered.reduce(0) { $0 + $1.duration }
        let activeDayStarts = Set(filtered.map { calendar.startOfDay(for: $0.timestamp) })
        let voice = filtered.filter { $0.sourceKind == .voiceRecording }
        let voiceWords = voice.reduce(0) { $0 + $1.words }
        let voiceDuration = voice.reduce(0) { $0 + $1.duration }
        let averageWPM = voiceDuration > 0 ? Double(voiceWords) / (voiceDuration / 60) : 0
        let typingDuration = Double(voiceWords) / DashboardStatsService.typingWPM * 60

        return StatsSnapshot(
            totalWords: totalWords,
            totalSessions: filtered.count,
            totalDuration: totalDuration,
            activeDays: activeDayStarts.count,
            averageWordsPerSession: Double(totalWords) / Double(filtered.count),
            averageSessionDuration: totalDuration / Double(filtered.count),
            longestStreak: longestStreak(days: activeDayStarts, calendar: calendar),
            enhancedSessions: filtered.filter(\.isEnhanced).count,
            estimatedTimeSaved: max(0, typingDuration - voiceDuration),
            averageWPM: averageWPM,
            averageTranscriptionSeconds: average(filtered.compactMap(\.transcriptionSeconds)),
            averageEnhancementSeconds: average(filtered.compactMap(\.enhancementSeconds)),
            averageTotalPipelineSeconds: average(filtered.compactMap(\.totalPipelineSeconds)),
            activity: activityBuckets(records: filtered, range: range, calendar: calendar),
            weekdays: weekdayBuckets(records: filtered, calendar: calendar),
            hours: hourBuckets(records: filtered, calendar: calendar),
            sources: sourceBuckets(records: filtered),
            destinations: destinationBuckets(records: filtered)
        )
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func normalizedDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite && duration > 0 ? duration : 0
    }

    private static func normalizedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func longestStreak(days: Set<Date>, calendar: Calendar) -> Int {
        let sorted = days.sorted()
        guard !sorted.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for index in 1..<sorted.count {
            let expected = calendar.date(byAdding: .day, value: 1, to: sorted[index - 1])
            if expected == sorted[index] {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private enum ActivityGranularity { case day, week, month }

    private static func activityBuckets(
        records: [StatsRecord], range: StatsRange, calendar: Calendar
    ) -> [StatsBucket] {
        let granularity: ActivityGranularity
        switch range {
        case .sevenDays, .thirtyDays: granularity = .day
        case .ninetyDays, .oneYear: granularity = .week
        case .allTime: granularity = .month
        }
        let grouped = Dictionary(grouping: records) { record -> Date in
            switch granularity {
            case .day:
                return calendar.startOfDay(for: record.timestamp)
            case .week:
                return calendar.dateInterval(of: .weekOfYear, for: record.timestamp)?.start
                    ?? calendar.startOfDay(for: record.timestamp)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: record.timestamp)
                return calendar.date(from: components) ?? calendar.startOfDay(for: record.timestamp)
            }
        }
        return grouped.map { date, values in
            StatsBucket(
                startDate: date,
                words: values.reduce(0) { $0 + $1.words },
                sessions: values.count,
                duration: values.reduce(0) { $0 + $1.duration }
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    private static func weekdayBuckets(
        records: [StatsRecord], calendar: Calendar
    ) -> [StatsCategoryBucket] {
        (0..<7).map { index in
            let weekday = ((calendar.firstWeekday - 1 + index) % 7) + 1
            let values = records.filter { calendar.component(.weekday, from: $0.timestamp) == weekday }
            return category(id: String(weekday), records: values)
        }
    }

    private static func hourBuckets(records: [StatsRecord], calendar: Calendar) -> [StatsCategoryBucket] {
        (0..<24).map { hour in
            category(
                id: String(hour),
                records: records.filter { calendar.component(.hour, from: $0.timestamp) == hour }
            )
        }
    }

    private static func sourceBuckets(records: [StatsRecord]) -> [StatsCategoryBucket] {
        MediaSourceKind.allCases.map { kind in
            category(id: kind.rawValue, records: records.filter { $0.sourceKind == kind })
        }.filter { $0.sessions > 0 }
    }

    private static func destinationBuckets(records: [StatsRecord]) -> [StatsCategoryBucket] {
        let grouped = Dictionary(grouping: records) { $0.destinationApp ?? "" }
        let sorted = grouped.map { name, values in category(id: name, records: values) }
            .sorted {
                if $0.words != $1.words { return $0.words > $1.words }
                if $0.sessions != $1.sessions { return $0.sessions > $1.sessions }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
        let known = sorted.filter { !$0.id.isEmpty }
        var result = Array(known.prefix(5))
        let remainder = Array(known.dropFirst(5))
        if !remainder.isEmpty {
            result.append(StatsCategoryBucket(
                id: "__other__",
                words: remainder.reduce(0) { $0 + $1.words },
                sessions: remainder.reduce(0) { $0 + $1.sessions },
                duration: remainder.reduce(0) { $0 + $1.duration }
            ))
        }
        if let unknown = sorted.first(where: { $0.id.isEmpty }) {
            result.append(StatsCategoryBucket(
                id: "__unknown__", words: unknown.words, sessions: unknown.sessions, duration: unknown.duration
            ))
        }
        return result
    }

    private static func category(id: String, records: [StatsRecord]) -> StatsCategoryBucket {
        StatsCategoryBucket(
            id: id,
            words: records.reduce(0) { $0 + $1.words },
            sessions: records.count,
            duration: records.reduce(0) { $0 + $1.duration }
        )
    }
}

enum StatsPresentation {
    static func formatNumber(_ value: Double, locale: Locale, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    static func formatDuration(_ duration: TimeInterval, locale: Locale) -> String {
        HomePresentation.formatCompactDuration(duration, locale: locale).isEmpty
            ? localized("0 m", locale: locale)
            : HomePresentation.formatCompactDuration(duration, locale: locale)
    }

    /// Sub-minute latency formatting for pipeline stage durations: milliseconds
    /// under one second ("850 ms"), otherwise seconds with one fraction digit ("4.3 s").
    static func formatLatency(_ seconds: Double, locale: Locale) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = seconds < 1 ? 0 : 1
        let measurement = seconds < 1
            ? Measurement(value: seconds * 1000, unit: UnitDuration.milliseconds)
            : Measurement(value: seconds, unit: UnitDuration.seconds)
        return formatter.string(from: measurement)
    }

    static func value(_ bucket: StatsBucket, metric: StatsMetric) -> Double {
        switch metric {
        case .words: return Double(bucket.words)
        case .sessions: return Double(bucket.sessions)
        case .duration: return bucket.duration
        }
    }

    static func value(_ bucket: StatsCategoryBucket, metric: StatsMetric) -> Double {
        switch metric {
        case .words: return Double(bucket.words)
        case .sessions: return Double(bucket.sessions)
        case .duration: return bucket.duration
        }
    }

    static func formattedValue(_ value: Double, metric: StatsMetric, locale: Locale) -> String {
        metric == .duration
            ? formatDuration(value, locale: locale)
            : formatNumber(value, locale: locale)
    }

    static func activityLabel(date: Date, range: StatsRange, locale: Locale, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(range == .allTime ? "MMM yyyy" : "MMM d")
        return formatter.string(from: date)
    }

    static func weekdayLabels(calendar: Calendar, locale: Locale) -> [String] {
        HomePresentation.weekdayLabels(calendar: calendar, locale: locale)
    }

    static func hourLabel(_ hour: Int, locale: Locale, calendar: Calendar) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        let localizedHourFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        formatter.setLocalizedDateFormatFromTemplate(localizedHourFormat.contains("a") ? "ha" : "H")
        return formatter.string(from: date)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
    }

    static func sourceLabel(_ id: String, locale: Locale) -> String {
        switch MediaSourceKind(rawValue: id) {
        case .voiceRecording: return localized("Voice", locale: locale)
        case .manualCapture: return localized("Manual capture", locale: locale)
        case .importedFile: return localized("Imported file", locale: locale)
        case .webLink: return localized("Web link", locale: locale)
        case nil: return id
        }
    }

    static func destinationLabel(_ id: String, locale: Locale) -> String {
        switch id {
        case "__other__": return localized("Other", locale: locale)
        case "__unknown__": return localized("Unknown", locale: locale)
        default: return id
        }
    }
}
