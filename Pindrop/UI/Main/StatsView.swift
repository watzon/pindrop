//
//  StatsView.swift
//  Pindrop
//
//  Created on 2026-07-11.
//

import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]

    @State private var selectedRange: StatsRange = .thirtyDays
    @State private var selectedMetric: StatsMetric = .words
    @State private var hasAppeared = false
    /// Aggregation cache keyed by history projection + range + calendar day.
    /// Metric/animation state must not re-run `StatsService.compute`.
    @State private var snapshotCache = StatsSnapshotCache()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        let now = Date()
        let historyProjection = StatsService.project(transcriptions)
        let snapshot = snapshotCache.snapshot(
            for: StatsSnapshotCache.Key(
                records: historyProjection,
                range: selectedRange,
                dayStart: calendar.startOfDay(for: now),
                firstWeekday: calendar.firstWeekday,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
            calendar: calendar,
            now: now
        )

        VStack(spacing: 0) {
            header(snapshot: snapshot)
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if snapshot.totalSessions == 0 {
                        emptyState
                            .padding(.top, 56)
                    } else {
                        overview(snapshot: snapshot)
                            .padding(.top, 36)
                        activity(snapshot: snapshot)
                            .padding(.top, 40)
                        patterns(snapshot: snapshot)
                            .padding(.top, 40)
                        breakdowns(snapshot: snapshot)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CompactScrollIndicatorConfigurator())
            }
        }
        .background(AppColors.contentBackground)
        .accessibilityIdentifier("stats.page")
        .onAppear { hasAppeared = true }
        .onChange(of: selectedRange) { _, _ in
            guard !reduceMotion else { return }
            hasAppeared = false
            DispatchQueue.main.async { hasAppeared = true }
        }
    }

    private func header(snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                title: localized("Stats", locale: locale),
                meta: rangeSummary(snapshot: snapshot)
            )

            Picker(localized("Time range", locale: locale), selection: $selectedRange) {
                ForEach(StatsRange.allCases) { range in
                    Text(range.title(locale: locale)).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 520, alignment: .leading)
            .accessibilityIdentifier("stats.range")
        }
    }

    private func rangeSummary(snapshot: StatsSnapshot) -> String {
        String(
            format: localized("%@ sessions in %@", locale: locale),
            StatsPresentation.formatNumber(Double(snapshot.totalSessions), locale: locale),
            selectedRange.title(locale: locale).lowercased(with: locale)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("No activity in this period", locale: locale))
                .font(FontLoader.font(family: .newsreader, size: 28, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
            Text(localized("Your stats will appear after you create transcriptions.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overview(snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: localized("Overview", locale: locale))

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 0, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 22
            ) {
                metric(
                    value: StatsPresentation.formatNumber(Double(snapshot.totalWords), locale: locale),
                    label: localized("Transcribed words", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatNumber(Double(snapshot.totalSessions), locale: locale),
                    label: localized("Sessions", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatDuration(snapshot.totalDuration, locale: locale),
                    label: localized("Audio duration", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatNumber(Double(snapshot.activeDays), locale: locale),
                    label: localized("Active days", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatNumber(snapshot.averageWordsPerSession, locale: locale),
                    label: localized("Average words / session", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatDuration(snapshot.averageSessionDuration, locale: locale),
                    label: localized("Average session", locale: locale)
                )
                metric(
                    value: String(format: localized("%d-day", locale: locale), snapshot.longestStreak),
                    label: localized("Longest streak", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatNumber(Double(snapshot.enhancedSessions), locale: locale),
                    label: localized("AI-enhanced", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatNumber(snapshot.averageWPM, locale: locale),
                    label: localized("Dictation words / min", locale: locale)
                )
                metric(
                    value: StatsPresentation.formatDuration(snapshot.estimatedTimeSaved, locale: locale),
                    label: localized("Estimated time saved", locale: locale)
                )
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(FontLoader.font(family: .jetbrainsMono, size: 22, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label.uppercased(with: locale))
                .font(FontLoader.font(family: .inter, size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(2)
        }
        .padding(.trailing, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func activity(snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: localized("Activity", locale: locale)) {
                Picker(localized("Metric", locale: locale), selection: $selectedMetric) {
                    ForEach(StatsMetric.allCases) { metric in
                        Text(metric.title(locale: locale)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .accessibilityIdentifier("stats.metric")
            }

            ActivityBars(
                buckets: snapshot.activity,
                range: selectedRange,
                metric: selectedMetric,
                locale: locale,
                calendar: calendar,
                hasAppeared: hasAppeared
            )
            .frame(height: 190)
            .accessibilityIdentifier("stats.chart.activity")
        }
    }

    private func patterns(snapshot: StatsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: localized("By weekday", locale: locale))
                let labels = StatsPresentation.weekdayLabels(calendar: calendar, locale: locale)
                CategoryBars(
                    buckets: snapshot.weekdays,
                    labels: Dictionary(uniqueKeysWithValues: zip(snapshot.weekdays.map(\.id), labels)),
                    metric: selectedMetric,
                    locale: locale,
                    hasAppeared: hasAppeared
                )
                .frame(height: 160)
                .accessibilityIdentifier("stats.chart.weekday")
            }

            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: 196)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: localized("Time of day", locale: locale))
                CategoryBars(
                    buckets: snapshot.hours,
                    labels: Dictionary(uniqueKeysWithValues: snapshot.hours.map { bucket in
                        (bucket.id, StatsPresentation.hourLabel(Int(bucket.id) ?? 0, locale: locale, calendar: calendar))
                    }),
                    metric: selectedMetric,
                    locale: locale,
                    labelStride: 4,
                    hasAppeared: hasAppeared
                )
                .frame(height: 160)
                .accessibilityIdentifier("stats.chart.hours")
            }
        }
    }

    private func breakdowns(snapshot: StatsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: localized("Sources", locale: locale))
                HorizontalStatsBars(
                    buckets: snapshot.sources,
                    label: { StatsPresentation.sourceLabel($0, locale: locale) },
                    metric: selectedMetric,
                    locale: locale,
                    hasAppeared: hasAppeared
                )
                .accessibilityIdentifier("stats.chart.sources")
            }

            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: 230)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: localized("Destinations", locale: locale))
                if snapshot.destinations.isEmpty {
                    Text(localized("No destination data", locale: locale))
                        .font(AppTypography.bodyMeta)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.top, 8)
                } else {
                    HorizontalStatsBars(
                        buckets: snapshot.destinations,
                        label: { StatsPresentation.destinationLabel($0, locale: locale) },
                        metric: selectedMetric,
                        locale: locale,
                        hasAppeared: hasAppeared
                    )
                    .accessibilityIdentifier("stats.chart.destinations")
                }
            }
        }
    }
}

private struct ActivityBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buckets: [StatsBucket]
    let range: StatsRange
    let metric: StatsMetric
    let locale: Locale
    let calendar: Calendar
    let hasAppeared: Bool
    @State private var selectedID: Date?
    @State private var hoveredID: Date?

    var body: some View {
        let maxValue = buckets.map { StatsPresentation.value($0, metric: metric) }.max() ?? 0
        let activeID = hoveredID ?? selectedID ?? buckets.max {
            StatsPresentation.value($0, metric: metric) < StatsPresentation.value($1, metric: metric)
        }?.id
        let active = buckets.first { $0.id == activeID }

        VStack(alignment: .leading, spacing: 10) {
            if let active {
                HStack(alignment: .firstTextBaseline) {
                    Text(StatsPresentation.activityLabel(
                        date: active.startDate, range: range, locale: locale, calendar: calendar
                    ))
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text(StatsPresentation.formattedValue(
                        StatsPresentation.value(active, metric: metric), metric: metric, locale: locale
                    ))
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.accent)
                    .contentTransition(.numericText())
                }
            }

            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .bottom, spacing: buckets.count > 40 ? 4 : 7) {
                        ForEach(buckets) { bucket in
                            let value = StatsPresentation.value(bucket, metric: metric)
                            let isActive = bucket.id == activeID
                            Button {
                                selectedID = bucket.id
                            } label: {
                                VStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(isActive ? AppColors.accent : AppColors.border)
                                        .frame(
                                            width: buckets.count > 40 ? 8 : 14,
                                            height: hasAppeared ? max(4, 112 * value / max(1, maxValue)) : 4
                                        )
                                        .frame(height: 112, alignment: .bottom)
                                    if buckets.count <= 30 {
                                        Text(StatsPresentation.activityLabel(
                                            date: bucket.startDate,
                                            range: range,
                                            locale: locale,
                                            calendar: calendar
                                        ))
                                        .font(FontLoader.font(family: .inter, size: 9, weight: .medium))
                                        .foregroundStyle(isActive ? AppColors.accent : AppColors.textTertiary)
                                        .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.plain)
                            .keyboardFocusRing(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .onHover { hovering in hoveredID = hovering ? bucket.id : (hoveredID == bucket.id ? nil : hoveredID) }
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.42),
                                value: hasAppeared
                            )
                            .accessibilityLabel("\(StatsPresentation.activityLabel(date: bucket.startDate, range: range, locale: locale, calendar: calendar)), \(StatsPresentation.formattedValue(value, metric: metric, locale: locale))")
                            .accessibilityAddTraits(isActive ? .isSelected : [])
                        }
                    }
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                    .background(CompactScrollIndicatorConfigurator())
                }
            }
        }
        .onChange(of: metric) { _, _ in selectedID = nil }
        .onChange(of: range) { _, _ in selectedID = nil }
    }
}

private struct CategoryBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buckets: [StatsCategoryBucket]
    let labels: [String: String]
    let metric: StatsMetric
    let locale: Locale
    var labelStride: Int = 1
    let hasAppeared: Bool
    @State private var selectedID: String?
    @State private var hoveredID: String?

    var body: some View {
        let maxValue = buckets.map { StatsPresentation.value($0, metric: metric) }.max() ?? 0
        let activeID = hoveredID ?? selectedID
        HStack(alignment: .bottom, spacing: buckets.count > 12 ? 3 : 9) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                let value = StatsPresentation.value(bucket, metric: metric)
                let isActive = bucket.id == activeID
                Button { selectedID = bucket.id } label: {
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isActive ? AppColors.accent : AppColors.border)
                            .frame(height: hasAppeared ? max(4, 112 * value / max(1, maxValue)) : 4)
                            .frame(height: 112, alignment: .bottom)
                        Text(index % labelStride == 0 ? (labels[bucket.id] ?? bucket.id) : "")
                            .font(FontLoader.font(family: .inter, size: 9, weight: .medium))
                            .foregroundStyle(isActive ? AppColors.accent : AppColors.textTertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: 11)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .keyboardFocusRing(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onHover { hovering in hoveredID = hovering ? bucket.id : (hoveredID == bucket.id ? nil : hoveredID) }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: hasAppeared)
                .accessibilityLabel("\(labels[bucket.id] ?? bucket.id), \(StatsPresentation.formattedValue(value, metric: metric, locale: locale))")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .onChange(of: metric) { _, _ in selectedID = nil }
    }
}

private struct HorizontalStatsBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let buckets: [StatsCategoryBucket]
    let label: (String) -> String
    let metric: StatsMetric
    let locale: Locale
    let hasAppeared: Bool
    @State private var selectedID: String?
    @State private var hoveredID: String?

    var body: some View {
        let maxValue = buckets.map { StatsPresentation.value($0, metric: metric) }.max() ?? 0
        VStack(spacing: 10) {
            ForEach(buckets) { bucket in
                let value = StatsPresentation.value(bucket, metric: metric)
                let isActive = bucket.id == (hoveredID ?? selectedID)
                Button { selectedID = bucket.id } label: {
                    HStack(spacing: 10) {
                        Text(label(bucket.id))
                            .font(AppTypography.bodyMeta)
                            .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                            .lineLimit(1)
                            .frame(width: 104, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppColors.border.opacity(0.55))
                                Capsule()
                                    .fill(isActive ? AppColors.accent : AppColors.textTertiary)
                                    .frame(width: hasAppeared ? geometry.size.width * value / max(1, maxValue) : 0)
                            }
                        }
                        .frame(height: 7)
                        Text(StatsPresentation.formattedValue(value, metric: metric, locale: locale))
                            .font(AppTypography.monoSmall)
                            .foregroundStyle(isActive ? AppColors.accent : AppColors.textTertiary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardFocusRing(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .onHover { hovering in hoveredID = hovering ? bucket.id : (hoveredID == bucket.id ? nil : hoveredID) }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: hasAppeared)
                .accessibilityLabel("\(label(bucket.id)), \(StatsPresentation.formattedValue(value, metric: metric, locale: locale))")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .onChange(of: metric) { _, _ in selectedID = nil }
    }
}

// MARK: - Snapshot cache

/// Recomputes `StatsSnapshot` only when the history projection, selected range,
/// or calendar-day boundary changes. Stored in `@State` so metric picker and
/// appear-animation flips reuse the same aggregate without re-aggregation.
/// Class init stays nonisolated for `@State` default construction under Swift 5.9;
/// mutation is method-isolated (`@MainActor` accessors only).
private final class StatsSnapshotCache {
    struct Key: Equatable {
        let records: [StatsRecord]
        let range: StatsRange
        let dayStart: Date
        let firstWeekday: Int
        let timeZoneIdentifier: String
    }

    private var key: Key?
    private var value: StatsSnapshot = .empty

    @MainActor
    func snapshot(for key: Key, calendar: Calendar, now: Date) -> StatsSnapshot {
        if self.key == key {
            return value
        }
        self.key = key
        value = StatsService.compute(
            records: key.records,
            range: key.range,
            calendar: calendar,
            now: now
        )
        return value
    }
}

#Preview("Stats") {
    StatsView()
        .frame(width: 980, height: 760)
        .modelContainer(PreviewContainer.withSampleData)
        .themeRefresh()
}
