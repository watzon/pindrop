//
//  DashboardView.swift
//  Pindrop
//
//  Home page (U4 scorched-earth restyle) — date kicker, hero, stats strip,
//  recent rows, THIS WEEK chart.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @ObservedObject private var indicatorState: FloatingIndicatorState
    @ObservedObject private var settingsStore: SettingsStore

    var onOpenHotkeys: (() -> Void)?
    var onViewAllHistory: (() -> Void)?
    var onNewTranscription: (() -> Void)?
    var onTranscribeFile: (() -> Void)?
    var onRecordMeeting: (() -> Void)?
    var onNewNote: (() -> Void)?

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(
        floatingIndicatorState: FloatingIndicatorState? = nil,
        settingsStore: SettingsStore? = nil,
        onOpenHotkeys: (() -> Void)? = nil,
        onViewAllHistory: (() -> Void)? = nil,
        onNewTranscription: (() -> Void)? = nil,
        onTranscribeFile: (() -> Void)? = nil,
        onRecordMeeting: (() -> Void)? = nil,
        onNewNote: (() -> Void)? = nil
    ) {
        self._indicatorState = ObservedObject(wrappedValue: floatingIndicatorState ?? FloatingIndicatorState())
        self._settingsStore = ObservedObject(wrappedValue: settingsStore ?? SettingsStore())
        self.onOpenHotkeys = onOpenHotkeys
        self.onViewAllHistory = onViewAllHistory
        self.onNewTranscription = onNewTranscription
        self.onTranscribeFile = onTranscribeFile
        self.onRecordMeeting = onRecordMeeting
        self.onNewNote = onNewNote
    }

    // MARK: - Stats

    private var calendar: Calendar { Calendar.current }

    private var recentRecords: [TranscriptionRecord] {
        Array(transcriptions.prefix(3))
    }

    private var isFirstRun: Bool {
        transcriptions.isEmpty
    }

    private func stats(now: Date) -> DashboardStats {
        DashboardStatsService.compute(
            records: transcriptions,
            calendar: calendar,
            now: now
        )
    }

    // MARK: - Body

    var body: some View {
        // Re-render at each calendar midnight so date kicker, WORDS TODAY, STREAK,
        // and the today-bar highlight do not freeze while the window stays open.
        // Schedule is calendar midnights only (no per-minute / per-second timers).
        TimelineView(HomeDayBoundarySchedule(calendar: calendar)) { _ in
            // Date() is re-sampled when the schedule fires and when records change.
            homeContent(now: Date())
        }
    }

    private func homeContent(now: Date) -> some View {
        let dashboardStats = stats(now: now)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroBlock(now: now, stats: dashboardStats)
                statsStrip(stats: dashboardStats)
                recentSection
                thisWeekChart(now: now, stats: dashboardStats)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.contentBackground)
    }

    // MARK: - Hero

    private func heroBlock(now: Date, stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(HomePresentation.dateKicker(date: now, locale: locale, calendar: calendar))
                .font(FontLoader.font(family: .inter, size: HomeLayoutMetrics.kickerSize, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(HomeLayoutMetrics.kickerTrackingEm * HomeLayoutMetrics.kickerSize)

            if isFirstRun {
                firstRunWelcome
                    .padding(.top, 8)
                    .padding(.bottom, HomeLayoutMetrics.heroBottomPadding)
            } else {
                heroSentence(stats: stats)
                    .padding(.top, 6)
                    .padding(.bottom, HomeLayoutMetrics.heroBottomPadding)

                let sub = HomePresentation.subLine(
                    dictationDuration: stats.dictationDurationThisWeek,
                    timeSaved: stats.timeSavedThisWeek,
                    locale: locale
                )
                if !sub.isEmpty {
                    Text(sub)
                        .font(AppTypography.bodyMeta)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(AppTypography.bodyMetaLineSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstRunWelcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Speak. It's written.", locale: locale))
                .font(FontLoader.font(family: .newsreader, size: HomeLayoutMetrics.heroFontSize, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
                .tracking(HomeLayoutMetrics.heroTrackingEm * HomeLayoutMetrics.heroFontSize)
                .lineSpacing(HomeLayoutMetrics.heroLineHeight - HomeLayoutMetrics.heroFontSize)

            let hotkey = settingsStore.toggleHotkey.isEmpty
                ? localized("⌥Space", locale: locale)
                : settingsStore.toggleHotkey
            Text(String(format: localized("Press %@ anywhere to start dictating.", locale: locale), hotkey))
                .font(AppTypography.bodyMeta)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func heroSentence(stats: DashboardStats) -> some View {
        let parts = HomePresentation.heroSentenceParts(
            wordsThisWeek: stats.wordsThisWeek,
            locale: locale
        )
        let heroFont = FontLoader.font(
            family: .newsreader,
            size: HomeLayoutMetrics.heroFontSize,
            weight: .regular
        )
        let metricFont = FontLoader.font(
            family: .newsreader,
            size: HomeLayoutMetrics.heroFontSize,
            weight: .medium,
            italic: true
        )
        let tracking = HomeLayoutMetrics.heroTrackingEm * HomeLayoutMetrics.heroFontSize
        let lineSpacing = HomeLayoutMetrics.heroLineHeight - HomeLayoutMetrics.heroFontSize

        return (
            Text(parts.before)
                .font(heroFont)
                .foregroundStyle(AppColors.textPrimary)
            + Text(parts.metric)
                .font(metricFont)
                .foregroundStyle(AppColors.accent)
            + Text(parts.after)
                .font(heroFont)
                .foregroundStyle(AppColors.textPrimary)
        )
        .tracking(tracking)
        .lineSpacing(lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Stats strip

    private func statsStrip(stats: DashboardStats) -> some View {
        HStack(spacing: 0) {
            homeStat(
                value: HomePresentation.formatGrouped(stats.wordsToday, locale: locale),
                label: localized("Words today", locale: locale)
            )

            statsDivider

            homeStat(
                value: HomePresentation.formatWPM(stats.wpmThisWeek, locale: locale),
                label: localized("Words / min", locale: locale)
            )

            statsDivider

            homeStat(
                value: HomePresentation.formatGrouped(stats.sessionsThisWeek, locale: locale),
                label: localized("Sessions", locale: locale)
            )

            statsDivider

            homeStat(
                value: HomePresentation.streakLabel(days: stats.streakDays, locale: locale),
                label: localized("Streak", locale: locale)
            )

            Spacer(minLength: 0)
        }
        .padding(.top, HomeLayoutMetrics.statsTopPadding)
        .padding(.bottom, HomeLayoutMetrics.statsBottomPadding)
    }

    private var statsDivider: some View {
        Rectangle()
            .fill(AppColors.border)
            .frame(width: HomeLayoutMetrics.statsDividerWidth, height: HomeLayoutMetrics.statsDividerHeight)
            .padding(.horizontal, HomeLayoutMetrics.statsGroupPadding)
    }

    private func homeStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: HomeLayoutMetrics.statsInnerGap) {
            Text(value)
                .font(FontLoader.font(
                    family: .jetbrainsMono,
                    size: HomeLayoutMetrics.statsNumberSize,
                    weight: .medium
                ))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()

            Text(label.uppercased(with: locale))
                .font(FontLoader.font(
                    family: .inter,
                    size: HomeLayoutMetrics.statsLabelSize,
                    weight: .semibold
                ))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(HomeLayoutMetrics.statsLabelTrackingEm * HomeLayoutMetrics.statsLabelSize)
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: localized("Recent", locale: locale), isFirst: true) {
                Button {
                    onViewAllHistory?()
                } label: {
                    Text(localized("Open Library →", locale: locale))
                        .font(FontLoader.font(family: .inter, size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }

            if recentRecords.isEmpty {
                emptyRecentHint
                    .padding(.top, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRecords) { record in
                        homeRecentRow(record)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var emptyRecentHint: some View {
        Text(localized("Your latest dictations will show up here.", locale: locale))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func homeRecentRow(_ record: TranscriptionRecord) -> some View {
        let kind = record.resolvedSourceKind
        let hasAudio = TranscriptionDetailAccess.shouldShowPlayback(for: record)
        let isExpired = record.managedMediaPath == nil && kind == .voiceRecording
        let preview: String = {
            if kind == .manualCapture {
                if let title = record.preferredTitle, !title.isEmpty { return title }
            }
            let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return record.preferredTitle ?? localized("Untitled", locale: locale)
            }
            return text
        }()
        let previewMeta: String? = {
            guard kind == .manualCapture else { return nil }
            let meta = record.meetingMetadataString(locale: locale)
            return meta.isEmpty ? nil : meta
        }()
        let showExpiredChip = isExpired || (!hasAudio && record.duration > 0 && kind == .voiceRecording)

        return LibraryRowChrome(
            timeText: Self.rowTimeFormatter.string(from: record.timestamp),
            preview: preview,
            previewMeta: previewMeta,
            destination: LibraryKindPresentation.destinationPill(appName: record.destinationAppName),
            icon: {
                Image(systemName: LibraryKindPresentation.systemImage(for: kind))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            },
            playChip: {
                PlayChip(
                    durationText: formatDuration(record.duration),
                    isExpired: showExpiredChip,
                    action: { onViewAllHistory?() }
                )
            },
            action: {
                // Reveal-in-library isn't wired yet; navigate to Library (spec U4).
                onViewAllHistory?()
            }
        )
        // Row chrome includes 24 pt horizontal padding; counteract outer 40 so lanes
        // sit flush with the page content edge the way Library rows do.
        .padding(.horizontal, -24)
    }

    // MARK: - THIS WEEK chart

    private func thisWeekChart(now: Date, stats: DashboardStats) -> some View {
        let buckets = stats.wordsPerWeekday
        let maxWords = buckets.max() ?? 0
        let labels = HomePresentation.weekdayLabels(calendar: calendar, locale: locale)
        let names = HomePresentation.weekdayNames(calendar: calendar, locale: locale)

        return VStack(alignment: .leading, spacing: HomeLayoutMetrics.chartSectionGap) {
            SectionHeader(title: localized("This week", locale: locale), isFirst: true)

            HStack(alignment: .bottom, spacing: 0) {
                HStack(alignment: .bottom, spacing: HomeLayoutMetrics.chartBarGap) {
                    ForEach(0..<7, id: \.self) { index in
                        let words = index < buckets.count ? buckets[index] : 0
                        let kind = HomePresentation.barDayKind(index: index, now: now, calendar: calendar)
                        let height: CGFloat = {
                            if kind == .future {
                                return HomeLayoutMetrics.chartStubHeight
                            }
                            return HomePresentation.barHeight(words: words, maxWords: maxWords)
                        }()
                        let isToday = kind == .today
                        let barColor: Color = isToday ? AppColors.accent : AppColors.border
                        let labelColor: Color = isToday ? AppColors.accent : AppColors.textTertiary
                        let weekdayLabel = index < labels.count ? labels[index] : ""
                        let weekdayName = index < names.count ? names[index] : weekdayLabel

                        VStack(spacing: HomeLayoutMetrics.chartLabelGap) {
                            UnevenRoundedRectangle(
                                topLeadingRadius: HomeLayoutMetrics.chartBarTopRadius,
                                bottomLeadingRadius: HomeLayoutMetrics.chartBarBottomRadius,
                                bottomTrailingRadius: HomeLayoutMetrics.chartBarBottomRadius,
                                topTrailingRadius: HomeLayoutMetrics.chartBarTopRadius,
                                style: .continuous
                            )
                            .fill(barColor)
                            .frame(width: HomeLayoutMetrics.chartBarWidth, height: height)
                            .frame(maxHeight: HomeLayoutMetrics.chartBarAreaHeight, alignment: .bottom)

                            Text(weekdayLabel)
                                .font(FontLoader.font(family: .inter, size: 11, weight: isToday ? .semibold : .medium))
                                .foregroundStyle(labelColor)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            HomePresentation.barAccessibilityLabel(
                                weekdayName: weekdayName,
                                words: words,
                                locale: locale
                            )
                        )
                    }
                }

                Spacer(minLength: 24)

                VStack(alignment: .trailing, spacing: HomeLayoutMetrics.statsInnerGap) {
                    Text(HomePresentation.formatGrouped(stats.wordsThisWeek, locale: locale))
                        .font(FontLoader.font(
                            family: .jetbrainsMono,
                            size: HomeLayoutMetrics.statsNumberSize,
                            weight: .medium
                        ))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()

                    Text(localized("Words so far", locale: locale).uppercased(with: locale))
                        .font(FontLoader.font(
                            family: .inter,
                            size: HomeLayoutMetrics.statsLabelSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(AppColors.textTertiary)
                        .tracking(HomeLayoutMetrics.statsLabelTrackingEm * HomeLayoutMetrics.statsLabelSize)
                }
                .padding(.bottom, HomeLayoutMetrics.weekTotalBottomPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, HomeLayoutMetrics.chartTopPadding)
    }
}

// MARK: - Day-boundary timeline

/// Fires once per calendar midnight (local), not on a fixed wall-clock interval.
/// Cheap: no per-minute / per-second ticks while the Home window is open.
private struct HomeDayBoundarySchedule: TimelineSchedule {
    let calendar: Calendar

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(calendar: calendar, startDate: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let calendar: Calendar
        private var upcoming: Date

        init(calendar: Calendar, startDate: Date) {
            self.calendar = calendar
            self.upcoming = HomePresentation.nextMidnight(after: startDate, calendar: calendar)
        }

        mutating func next() -> Date? {
            let value = upcoming
            // Advance by one calendar day from this midnight so DST stays correct.
            upcoming = HomePresentation.nextMidnight(after: value, calendar: calendar)
            return value
        }
    }
}

#Preview("Dashboard - With Data") {
    DashboardView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Empty") {
    DashboardView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Dark") {
    DashboardView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.dark)
}
