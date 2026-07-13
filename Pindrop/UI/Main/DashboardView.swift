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
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @ObservedObject private var settingsStore: SettingsStore
    /// Aggregation cache keyed by record projection + calendar day. Hover/selection
    /// live in chart children so pointer movement cannot invalidate this work.
    @State private var statsCache = DashboardStatsCache()
    @State private var showMeetingCaptureOptions = false

    var onOpenHotkeys: (() -> Void)?
    var onViewAllHistory: (() -> Void)?
    var onShowMoreStats: (() -> Void)?
    var onOpenHistoryRecord: ((UUID) -> Void)?
    var onNewTranscription: (() -> Void)?
    var onTranscribeFile: (() -> Void)?
    var onRecordMeeting: ((Int?) -> Void)?
    var onNewNote: (() -> Void)?
    var onDownloadDiarizationModel: (() -> Void)?
    var recordingState: RecordingFeatureState?

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(
        floatingIndicatorState: FloatingIndicatorState? = nil,
        settingsStore: SettingsStore? = nil,
        recordingState: RecordingFeatureState? = nil,
        onOpenHotkeys: (() -> Void)? = nil,
        onViewAllHistory: (() -> Void)? = nil,
        onShowMoreStats: (() -> Void)? = nil,
        onOpenHistoryRecord: ((UUID) -> Void)? = nil,
        onNewTranscription: (() -> Void)? = nil,
        onTranscribeFile: (() -> Void)? = nil,
        onRecordMeeting: ((Int?) -> Void)? = nil,
        onNewNote: (() -> Void)? = nil,
        onDownloadDiarizationModel: (() -> Void)? = nil
    ) {
        // Indicator state is owned by the shell chrome; Home must not observe it.
        _ = floatingIndicatorState
        self._settingsStore = ObservedObject(wrappedValue: settingsStore ?? SettingsStore())
        self.recordingState = recordingState
        self.onOpenHotkeys = onOpenHotkeys
        self.onViewAllHistory = onViewAllHistory
        self.onShowMoreStats = onShowMoreStats
        self.onOpenHistoryRecord = onOpenHistoryRecord
        self.onNewTranscription = onNewTranscription
        self.onTranscribeFile = onTranscribeFile
        self.onRecordMeeting = onRecordMeeting
        self.onNewNote = onNewNote
        self.onDownloadDiarizationModel = onDownloadDiarizationModel
    }

    // MARK: - Stats

    private var calendar: Calendar { Calendar.current }

    private var recentRecords: [TranscriptionRecord] {
        Array(transcriptions.prefix(5))
    }

    private var isFirstRun: Bool {
        transcriptions.isEmpty
    }

    /// Sendable value projection for cache invalidation (data changes, not object identity).
    private var recordProjection: [StatsSample] {
        transcriptions.map(DashboardStatsService.sample(from:))
    }

    private func stats(now: Date) -> DashboardStats {
        statsCache.stats(
            for: DashboardStatsCache.Key(
                samples: recordProjection,
                dayStart: calendar.startOfDay(for: now),
                firstWeekday: calendar.firstWeekday,
                timeZoneIdentifier: calendar.timeZone.identifier
            ),
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
        return ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if let setupIssue = recordingState?.setupIssue {
                    diarizationSetupIssueBanner(
                        message: setupIssue,
                        isDownloading: recordingState?.isDiarizationModelDownloading ?? false,
                        progress: recordingState?.diarizationModelDownloadProgress ?? 0.0
                    )
                        .padding(.bottom, 16)
                }

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
        .sheet(isPresented: $showMeetingCaptureOptions) {
            MeetingCaptureOptionsSheet { expectedSpeakerCount in
                onRecordMeeting?(expectedSpeakerCount)
            }
        }
    }

    private func requestMeetingCapture() {
        guard onRecordMeeting != nil else { return }
        showMeetingCaptureOptions = true
    }

    private func diarizationSetupIssueBanner(
        message: String,
        isDownloading: Bool,
        progress: Double
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDownloading ? "arrow.down.circle" : "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(isDownloading ? AppColors.accent : AppColors.warning)

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(AppColors.accent)
                        .frame(maxWidth: 180)
                        .accessibilityValue("\(Int(progress * 100))%")
                }
            } else {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !isDownloading, onDownloadDiarizationModel != nil {
                Button(localized("Download model", locale: locale)) {
                    onDownloadDiarizationModel?()
                }
                .buttonStyle(.plain)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .accessibilityIdentifier("diarizationSetupIssueDownloadButton")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.warningBackground)
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value), \(label)")
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: localized("Recent", locale: locale), isFirst: true) {
                Button {
                    onViewAllHistory?()
                } label: {
                    HStack(spacing: 3) {
                        Text(localized("Open Library", locale: locale))
                        Image(systemName: "arrow.right")
                            .flipsForRightToLeftLayoutDirection(true)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Your latest dictations will show up here.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if onRecordMeeting != nil {
                Button {
                    requestMeetingCapture()
                } label: {
                    Text(localized("Record Meeting…", locale: locale))
                        .font(AppTypography.labelSemibold)
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.button.recordMeeting")
            }
        }
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
            destination: LibraryKindPresentation.destinationPill(
                appName: record.destinationAppName,
                layoutDirection: layoutDirection
            ),
            icon: {
                Image(systemName: LibraryKindPresentation.systemImage(for: kind))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            },
            playChip: {
                PlayChip(
                    durationText: formatDuration(record.duration),
                    isExpired: showExpiredChip,
                    action: { onOpenHistoryRecord?(record.id) }
                )
            },
            action: {
                onOpenHistoryRecord?(record.id)
            }
        )
        // Row chrome includes 24 pt horizontal padding; counteract outer 40 so lanes
        // sit flush with the page content edge the way Library rows do.
        .padding(.horizontal, -24)
    }

    // MARK: - THIS WEEK chart

    private func thisWeekChart(now: Date, stats: DashboardStats) -> some View {
        HStack(alignment: .top, spacing: HomeLayoutMetrics.chartPanelGap) {
            DashboardWeeklyBarsChart(
                buckets: stats.wordsPerWeekday,
                now: now,
                locale: locale,
                calendar: calendar
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minWidth: HomeLayoutMetrics.chartMinimumWidth,
                maxWidth: HomeLayoutMetrics.chartMaximumWidth,
                alignment: .leading
            )

            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: HomeLayoutMetrics.chartPanelDividerHeight)
                .padding(.top, 6)

            DashboardActivityHeatmap(
                buckets: stats.wordsPerActivityDay,
                streakDays: stats.streakDays,
                now: now,
                locale: locale,
                calendar: calendar,
                onShowMoreStats: onShowMoreStats
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.top, HomeLayoutMetrics.chartTopPadding)
    }
}

// MARK: - Weekly bars (hover/selection isolated)

/// Owns weekly-bar selection and hover so pointer movement invalidates only this subtree.
private struct DashboardWeeklyBarsChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let buckets: [Int]
    let now: Date
    let locale: Locale
    let calendar: Calendar

    @State private var selectedWeekdayIndex: Int?
    @State private var hoveredWeekdayIndex: Int?
    @State private var chartHasAppeared = false

    var body: some View {
        let maxWords = buckets.max() ?? 0
        let labels = HomePresentation.weekdayLabels(calendar: calendar, locale: locale)
        let names = HomePresentation.weekdayNames(calendar: calendar, locale: locale)
        let todayIndex = HomePresentation.todayBarIndex(now: now, calendar: calendar)
        let activeIndex = hoveredWeekdayIndex.flatMap { $0 <= todayIndex ? $0 : nil }
            ?? selectedWeekdayIndex.flatMap { $0 <= todayIndex ? $0 : nil }
            ?? todayIndex
        let activeWords = activeIndex < buckets.count ? buckets[activeIndex] : 0
        let activeName = activeIndex < names.count ? names[activeIndex] : ""

        VStack(alignment: .leading, spacing: HomeLayoutMetrics.chartSectionGap) {
            SectionHeader(
                title: localized("This week", locale: locale),
                trailing: HomePresentation.wordMetric(count: activeWords, locale: locale),
                isFirst: true
            )

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)
                    .padding(.bottom, 19)

                HStack(alignment: .bottom, spacing: HomeLayoutMetrics.chartBarGap) {
                    ForEach(0..<7, id: \.self) { index in
                        let words = index < buckets.count ? buckets[index] : 0
                        let kind = HomePresentation.barDayKind(index: index, now: now, calendar: calendar)
                        let height: CGFloat = {
                            if kind == .future {
                                return 0
                            }
                            return HomePresentation.barHeight(words: words, maxWords: maxWords)
                        }()
                        let isActive = index == activeIndex
                        let barColor: Color = isActive ? AppColors.accent : AppColors.border
                        let labelColor: Color = isActive ? AppColors.accent : AppColors.textTertiary
                        let weekdayLabel = index < labels.count ? labels[index] : ""
                        let weekdayName = index < names.count ? names[index] : weekdayLabel

                        Button {
                            selectedWeekdayIndex = index
                        } label: {
                            VStack(spacing: HomeLayoutMetrics.chartLabelGap) {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: HomeLayoutMetrics.chartBarTopRadius,
                                    bottomLeadingRadius: HomeLayoutMetrics.chartBarBottomRadius,
                                    bottomTrailingRadius: HomeLayoutMetrics.chartBarBottomRadius,
                                    topTrailingRadius: HomeLayoutMetrics.chartBarTopRadius,
                                    style: .continuous
                                )
                                .fill(barColor)
                                .frame(
                                    width: HomeLayoutMetrics.chartBarWidth,
                                    height: chartHasAppeared ? height : 0
                                )
                                .frame(maxHeight: HomeLayoutMetrics.chartBarAreaHeight, alignment: .bottom)
                                .animation(
                                    reduceMotion
                                        ? nil
                                        : .easeOut(duration: 0.42).delay(Double(index) * 0.035),
                                    value: chartHasAppeared
                                )
                                .appAnimation(.normal, value: words)

                                Text(weekdayLabel)
                                    .font(FontLoader.font(
                                        family: .inter,
                                        size: 11,
                                        weight: isActive ? .semibold : .medium
                                    ))
                                    .foregroundStyle(labelColor)
                            }
                            .frame(width: HomeLayoutMetrics.chartBarWidth)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(kind == .future)
                        .keyboardFocusRing(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .appAnimation(.fast, value: isActive)
                        .onHover { hovering in
                            guard kind != .future else { return }
                            if hovering {
                                hoveredWeekdayIndex = index
                            } else if hoveredWeekdayIndex == index {
                                hoveredWeekdayIndex = nil
                            }
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(activeName.uppercased(with: locale))
                .font(FontLoader.font(
                    family: .inter,
                    size: HomeLayoutMetrics.statsLabelSize,
                    weight: .semibold
                ))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(HomeLayoutMetrics.statsLabelTrackingEm * HomeLayoutMetrics.statsLabelSize)
                .appAnimation(.fast, value: activeIndex)
        }
        .onAppear {
            chartHasAppeared = true
        }
    }
}

// MARK: - Activity heatmap (hover isolated)

/// Owns 53×7 heatmap hover so pointer movement invalidates only this subtree.
private struct DashboardActivityHeatmap: View {
    let buckets: [Int]
    let streakDays: Int
    let now: Date
    let locale: Locale
    let calendar: Calendar
    var onShowMoreStats: (() -> Void)?

    @State private var hoveredActivityIndex: Int?

    var body: some View {
        let maxWords = buckets.max() ?? 0
        let startDate = HomePresentation.activityStartDate(now: now, calendar: calendar)
        let leadingBlankCount = startDate.map {
            HomePresentation.activityLeadingBlankCount(startDate: $0, calendar: calendar)
        } ?? 0
        let gridStartDate = startDate.flatMap {
            HomePresentation.activityGridStartDate(startDate: $0, calendar: calendar)
        }

        VStack(alignment: .leading, spacing: HomeLayoutMetrics.chartSectionGap) {
            SectionHeader(title: localized("History", locale: locale), isFirst: true) {
                Button {
                    onShowMoreStats?()
                } label: {
                    HStack(spacing: 3) {
                        Text(localized("Show more stats", locale: locale))
                        Image(systemName: "arrow.right")
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .font(FontLoader.font(family: .inter, size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .keyboardFocusRing(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityIdentifier("home.button.showMoreStats")
                .help(localized("Show more stats", locale: locale))
            }

            if let startDate, let gridStartDate {
                GeometryReader { geometry in
                    let cellSize = activityCellSize(availableWidth: geometry.size.width)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: HomeLayoutMetrics.activityCellGap) {
                            ForEach(0..<53, id: \.self) { weekIndex in
                                Text(HomePresentation.activityMonthLabel(
                                    weekIndex: weekIndex,
                                    startDate: gridStartDate,
                                    calendar: calendar,
                                    locale: locale
                                ))
                                .font(FontLoader.font(family: .inter, size: 9, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: cellSize, alignment: .leading)
                            }
                        }

                        HStack(spacing: HomeLayoutMetrics.activityCellGap) {
                            ForEach(0..<53, id: \.self) { weekIndex in
                                VStack(spacing: HomeLayoutMetrics.activityCellGap) {
                                    ForEach(0..<7, id: \.self) { dayIndex in
                                        let gridIndex = weekIndex * 7 + dayIndex
                                        let bucketIndex = gridIndex - leadingBlankCount

                                        if buckets.indices.contains(bucketIndex) {
                                            let words = buckets[bucketIndex]
                                            let date = calendar.date(
                                                byAdding: .day,
                                                value: bucketIndex,
                                                to: startDate
                                            ) ?? startDate
                                            let isToday = calendar.isDate(date, inSameDayAs: now)
                                            let isHovered = hoveredActivityIndex == bucketIndex

                                            RoundedRectangle(cornerRadius: min(2, cellSize / 4), style: .continuous)
                                                .fill(activityColor(intensity: HomePresentation.activityIntensity(
                                                    words: words,
                                                    maxWords: maxWords
                                                )))
                                                .frame(width: cellSize, height: cellSize)
                                                .overlay {
                                                    if isToday || isHovered {
                                                        RoundedRectangle(
                                                            cornerRadius: min(2, cellSize / 4),
                                                            style: .continuous
                                                        )
                                                        .strokeBorder(
                                                            isHovered ? AppColors.textPrimary : AppColors.accent,
                                                            lineWidth: isHovered ? 1.5 : 1
                                                        )
                                                    }
                                                }
                                                .scaleEffect(isHovered ? 1.35 : 1)
                                                .zIndex(isHovered ? 1 : 0)
                                                .contentShape(Rectangle())
                                                .onHover { hovering in
                                                    if hovering {
                                                        hoveredActivityIndex = bucketIndex
                                                    } else if hoveredActivityIndex == bucketIndex {
                                                        hoveredActivityIndex = nil
                                                    }
                                                }
                                                .appAnimation(.fast, value: isHovered)
                                                .accessibilityLabel(HomePresentation.activityAccessibilityLabel(
                                                    date: date,
                                                    words: words,
                                                    calendar: calendar,
                                                    locale: locale
                                                ))
                                        } else {
                                            Color.clear
                                                .frame(width: cellSize, height: cellSize)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        if let hoveredActivityIndex,
                           buckets.indices.contains(hoveredActivityIndex),
                           let date = calendar.date(
                               byAdding: .day,
                               value: hoveredActivityIndex,
                               to: startDate
                           ) {
                            let gridIndex = hoveredActivityIndex + leadingBlankCount
                            let weekIndex = gridIndex / 7
                            let dayIndex = gridIndex % 7
                            let cellX = CGFloat(weekIndex) * (cellSize + HomeLayoutMetrics.activityCellGap)
                            let cellY = 18 + CGFloat(dayIndex) * (cellSize + HomeLayoutMetrics.activityCellGap)
                            let tooltipX = min(
                                max(0, cellX - 76),
                                max(0, geometry.size.width - 160)
                            )
                            let tooltipY = dayIndex < 4
                                ? cellY + cellSize + 6
                                : max(0, cellY - 48)

                            activityTooltip(
                                date: date,
                                words: buckets[hoveredActivityIndex]
                            )
                            .offset(x: tooltipX, y: tooltipY)
                            .zIndex(10)
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: HomeLayoutMetrics.activityGridHeight)

                HStack(spacing: 4) {
                    Text(localized("Streak", locale: locale).uppercased(with: locale))
                    Text(HomePresentation.streakLabel(days: streakDays, locale: locale))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer(minLength: 8)

                    ForEach(0...4, id: \.self) { intensity in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(activityColor(intensity: intensity))
                            .frame(width: 7, height: 7)
                    }
                }
                .font(FontLoader.font(family: .inter, size: 9, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private func activityCellSize(availableWidth: CGFloat) -> CGFloat {
        let gapsWidth = HomeLayoutMetrics.activityCellGap * 52
        let fittedSize = (availableWidth - gapsWidth) / 53
        return min(
            HomeLayoutMetrics.activityMaximumCellSize,
            max(HomeLayoutMetrics.activityMinimumCellSize, fittedSize)
        )
    }

    private func activityTooltip(date: Date, words: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(HomePresentation.activityDateLabel(
                date: date,
                calendar: calendar,
                locale: locale
            ).uppercased(with: locale))
                .font(FontLoader.font(family: .inter, size: 9, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

            Text(HomePresentation.wordMetric(count: words, locale: locale))
                .font(FontLoader.font(family: .jetbrainsMono, size: 11, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 136, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.elevatedSurface, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        }
        .shadow(color: AppColors.shadowColor.opacity(0.18), radius: 8, y: 4)
    }

    private func activityColor(intensity: Int) -> Color {
        switch intensity {
        case 1: AppColors.accent.opacity(0.24)
        case 2: AppColors.accent.opacity(0.44)
        case 3: AppColors.accent.opacity(0.68)
        case 4: AppColors.accent
        default: AppColors.border.opacity(0.55)
        }
    }
}

// MARK: - Dashboard stats cache

/// Recomputes dashboard aggregates only when the record projection or calendar day changes.
/// Class init stays nonisolated for `@State` default construction under Swift 5.9;
/// mutation is method-isolated (`@MainActor` accessors only).
private final class DashboardStatsCache {
    struct Key: Equatable {
        let samples: [StatsSample]
        let dayStart: Date
        let firstWeekday: Int
        let timeZoneIdentifier: String
    }

    private var key: Key?
    private var value: DashboardStats = .empty

    @MainActor
    func stats(for key: Key, calendar: Calendar, now: Date) -> DashboardStats {
        if self.key == key {
            return value
        }
        self.key = key
        value = DashboardStatsService.compute(
            samples: key.samples,
            calendar: calendar,
            now: now
        )
        return value
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
