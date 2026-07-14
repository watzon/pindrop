//
//  HistoryView.swift
//  Pindrop
//
//  Library page (U3 scorched-earth restyle).
//

import SwiftUI
import SwiftData
import Foundation
import AppKit
import UniformTypeIdentifiers

struct HistoryLoadRequest: Equatable {
    let query: String
    let filter: HistoryStore.HistoryFilter
    let sort: MediaLibrarySortMode

    static func isCurrent(
        _ request: HistoryLoadRequest,
        generation: UInt,
        activeRequest: HistoryLoadRequest?,
        activeGeneration: UInt
    ) -> Bool {
        request == activeRequest && generation == activeGeneration
    }
}

struct HistoryView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var recordIDToOpen: UUID? = nil
    var mediaTranscriptionState: MediaTranscriptionFeatureState?
    var recordingState: RecordingFeatureState?
    var settingsStore: SettingsStore?
    var onImportMediaFiles: (([URL], TranscriptionJobOptions) -> Void)?
    var onSubmitMediaLink: ((String, TranscriptionJobOptions) -> Void)?
    var onStartMeetingCapture: ((Int?) -> Void)?
    var onDownloadDiarizationModel: (() -> Void)?

    // MARK: - State

    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedFilter: LibraryFilterChip = .all
    @State private var selectedSort: MediaLibrarySortMode = .newest
    @State private var errorMessage: String?
    @State private var selectedTranscriptionID: PersistentIdentifier?
    @State private var expandedTranscriptionID: PersistentIdentifier?
    @State private var detailRecord: TranscriptionRecord?
    @State private var pendingDeletionRecord: TranscriptionRecord?
    @State private var isLoading = true
    @State private var visibleTranscriptions: [TranscriptionRecord] = []
    /// Grouped sections cached with the visible records so selection-only
    /// updates do not re-run day grouping over every loaded page.
    @State private var groupedSections: [LibraryDaySection] = []
    @State private var totalCount: Int = 0
    @State private var totalSpokenDuration: TimeInterval = 0
    @State private var transcriptionSnapshot: HistoryStore.TranscriptionSnapshot?
    @State private var snapshotRequest: HistoryLoadRequest?
    @State private var snapshotGeneration: UInt?
    @State private var hasMorePages = true
    @State private var currentOffset = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var paginationTask: Task<Void, Never>?
    @State private var requestGeneration: UInt = 0
    @State private var activeRequest: HistoryLoadRequest?
    @State private var paginationGeneration: UInt = 0
    @State private var keyMonitor: Any?
    @State private var isDropTargeted = false
    @State private var showPasteLinkSheet = false
    @State private var pasteLinkText = ""
    @State private var transcribeMenuAnchorView: NSView?
    @State private var isSpeakerDiarizationEnabled = true
    @State private var expectedSpeakerCount: Int?
    @State private var showMeetingCaptureOptions = false

    @Query private var mediaFolders: [MediaFolder]

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let pageSize = 50

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var historyStore: HistoryStore {
        HistoryStore(
            modelContext: modelContext,
            speakerIdentityService: SpeakerIdentityService(modelContext: modelContext)
        )
    }

    private var retention: DictationAudioRetention {
        settingsStore?.dictationAudioRetention ?? .days7
    }

    private var headerMetaText: String {
        LibraryHeaderMeta.text(
            recordingCount: totalCount,
            spokenDuration: totalSpokenDuration,
            locale: locale
        )
    }

    private var newestFirstGrouping: Bool {
        selectedSort != .oldest
    }

    private var defaultJobOptions: TranscriptionJobOptions {
        Self.makeJobOptions(
            modelName: settingsStore?.selectedModel ?? "",
            language: settingsStore?.selectedAppLanguage ?? .automatic,
            diarizationEnabled: isSpeakerDiarizationEnabled,
            expectedSpeakerCount: expectedSpeakerCount
        )
    }

    static func makeJobOptions(
        modelName: String,
        language: AppLanguage,
        diarizationEnabled: Bool,
        expectedSpeakerCount: Int? = nil
    ) -> TranscriptionJobOptions {
        TranscriptionJobOptions(
            modelName: modelName,
            language: language,
            outputFormat: .plainText,
            diarizationEnabled: diarizationEnabled,
            expectedSpeakerCount: diarizationEnabled ? expectedSpeakerCount : nil
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let record = detailRecord {
                MediaTranscriptionDetailView(
                    record: record,
                    folders: folders,
                    onBack: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            detailRecord = nil
                        }
                    },
                    onAssignFolder: { folder in assignRecord(record, to: folder) },
                    onRemoveFromFolder: {
                        if record.folder != nil {
                            removeRecordFromFolder(record)
                        }
                    },
                    onAssignSpeakerProfile: { speakerID, profileID in
                        assignSpeakerProfile(for: record, speakerID: speakerID, profileID: profileID)
                    },
                    onUnassignSpeakerProfile: { speakerID in
                        unassignSpeakerProfile(for: record, speakerID: speakerID)
                    },
                    onCreateSpeakerProfile: { speakerID, name, notes in
                        createAndAssignSpeakerProfile(
                            for: record,
                            speakerID: speakerID,
                            name: name,
                            notes: notes
                        )
                    },
                    onDelete: { pendingDeletionRecord = record }
                )
                .background(AppColors.contentBackground)
            } else {
                libraryListChrome
            }
        }
        .task(id: "\(trimmedSearchText)_\(selectedFilter.rawValue)_\(selectedSort.rawValue)") {
            reloadTranscriptions()
        }
        .task(id: recordIDToOpen) {
            guard let recordIDToOpen,
                  let record = try? historyStore.fetchRecord(with: recordIDToOpen) else { return }
            handleRowTap(record)
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            refreshVisibleTranscriptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHistoryRecord)) { notification in
            guard let idString = notification.userInfo?["recordID"] as? String,
                  let id = UUID(uuidString: idString),
                  let record = try? historyStore.fetchRecord(with: id) else { return }
            handleRowTap(record)
        }
        .confirmationDialog(
            localized("Delete transcription?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionRecord != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionRecord = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                confirmDeletePendingRecord()
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                pendingDeletionRecord = nil
            }
        } message: {
            Text(localized("This will permanently remove the transcript and its managed media file.", locale: locale))
        }
        .sheet(isPresented: $showPasteLinkSheet) {
            pasteLinkSheet
        }
        .sheet(isPresented: $showMeetingCaptureOptions) {
            MeetingCaptureOptionsSheet { expectedSpeakerCount in
                onStartMeetingCapture?(expectedSpeakerCount)
            }
        }
        .onAppear {
            installKeyMonitorIfNeeded()
            consumePendingSearchFocusIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
            cancelManagedLoads()
        }
        .onChange(of: detailRecord?.persistentModelID) { _, _ in
            if detailRecord == nil {
                installKeyMonitorIfNeeded()
            } else {
                removeKeyMonitor()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusHistorySearch)) { _ in
            applySearchFocus()
        }
    }

    // MARK: - Library list chrome

    private var libraryListChrome: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            filterRow
                .padding(.horizontal, 40)
                .padding(.bottom, 12)
                .background(AppColors.contentBackground)

            if let setupIssue = activeSetupIssue {
                diarizationSetupIssueBanner(
                    message: setupIssue,
                    isDownloading: isDiarizationModelDownloading,
                    progress: diarizationModelDownloadProgress
                )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }

            if let mediaState = mediaTranscriptionState {
                importProgressSection(state: mediaState)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }

            contentArea
                .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
        .dropDestination(for: URL.self, action: { urls, _ in
            handleDroppedFiles(urls)
            return true
        }, isTargeted: { targeted in
            isDropTargeted = targeted
        })
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColors.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var activeSetupIssue: String? {
        mediaTranscriptionState?.setupIssue ?? recordingState?.setupIssue
    }

    private var isDiarizationModelDownloading: Bool {
        mediaTranscriptionState?.isDiarizationModelDownloading
            ?? recordingState?.isDiarizationModelDownloading
            ?? false
    }

    private var diarizationModelDownloadProgress: Double {
        mediaTranscriptionState?.diarizationModelDownloadProgress
            ?? recordingState?.diarizationModelDownloadProgress
            ?? 0.0
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

    // MARK: - Header

    private var headerSection: some View {
        PageHeader(title: localized("Library", locale: locale), meta: headerMetaText) {
            HStack(spacing: 10) {
                if onImportMediaFiles != nil || onSubmitMediaLink != nil || onStartMeetingCapture != nil {
                    importMenu
                }
                SearchFieldChrome(
                    text: $searchText,
                    placeholder: localized("Search", locale: locale),
                    showsKeyboardHint: true,
                    isFocused: $isSearchFieldFocused
                )
                .frame(width: 240)
            }
        }
    }

    // A true split button. SwiftUI's Menu styles kept fighting the design
    // (collapsed composite labels, force-tinted white arrow, menu anchored to
    // the chevron instead of the button) — so the chevron is a plain Button
    // that pops a real NSMenu anchored at the button's leading edge.
    private var importMenu: some View {
        HStack(spacing: 0) {
            Button {
                importFilesViaOpenPanel()
            } label: {
                Text(localized("Transcribe", locale: locale))
                    .font(AppTypography.labelSemibold)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized("Import media", locale: locale))

            Rectangle()
                .fill(AppColors.contentBackground.opacity(0.35))
                .frame(width: 1, height: 16)

            Button {
                presentTranscribeMenu()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Transcribe options", locale: locale))
        }
        .foregroundStyle(AppColors.contentBackground)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.accent)
        )
        .background(
            TranscribeMenuAnchor { view in
                transcribeMenuAnchorView = view
            }
        )
        .fixedSize()
        .fixedSize()
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(LibraryFilterChip.allCases) { chip in
                FilterChip(
                    title: chip.title(locale: locale),
                    isSelected: selectedFilter == chip
                ) {
                    withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
                        selectedFilter = chip
                        expandedTranscriptionID = nil
                    }
                }
            }

            Spacer(minLength: 12)

            sortChip
        }
    }

    private var sortChip: some View {
        Menu {
            Button {
                selectedSort = .newest
            } label: {
                sortMenuLabel(for: .newest)
            }
            Button {
                selectedSort = .oldest
            } label: {
                sortMenuLabel(for: .oldest)
            }
        } label: {
            FilterChip(
                title: selectedSort.title(locale: locale),
                systemImage: "arrow.up.arrow.down",
                isSelected: false,
                action: {}
            )
            .allowsHitTesting(false)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(localized("Sort by", locale: locale))
    }

    @ViewBuilder
    private func sortMenuLabel(for mode: MediaLibrarySortMode) -> some View {
        if selectedSort == mode {
            Label(mode.title(locale: locale), systemImage: "checkmark")
        } else {
            Text(mode.title(locale: locale))
        }
    }

    // MARK: - Import progress

    @ViewBuilder
    private func importProgressSection(state: MediaTranscriptionFeatureState) -> some View {
        let jobs = activeImportJobs(state: state)
        if !jobs.isEmpty {
            VStack(spacing: 6) {
                ForEach(jobs, id: \.id) { job in
                    importProgressRow(job: job)
                }
            }
        }
    }

    private func activeImportJobs(state: MediaTranscriptionFeatureState) -> [MediaTranscriptionJobState] {
        var jobs: [MediaTranscriptionJobState] = []
        if let current = state.currentJob, current.stage != .completed, current.stage != .failed {
            jobs.append(current)
        }
        jobs.append(contentsOf: state.pendingJobs)
        return jobs
    }

    private func importProgressRow(job: MediaTranscriptionJobState) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.request.displayName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if !job.detail.isEmpty {
                    Text(job.detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let progress = job.progress {
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if isLoading {
            loadingView
        } else if visibleTranscriptions.isEmpty {
            emptyView
        } else {
            transcriptionsList
        }
    }

    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(AppColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.warning)

            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Button(localized("Dismiss", locale: locale)) {
                self.errorMessage = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        let (title, subtitle) = emptyStateContent
        return VStack(spacing: 12) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textSecondary)
            Text(subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, AppTheme.Spacing.huge)
    }

    private var emptyStateContent: (title: String, subtitle: String) {
        if !trimmedSearchText.isEmpty {
            return (
                localized("No results", locale: locale),
                localized("Try a different search term or filter.", locale: locale)
            )
        }

        switch selectedFilter {
        case .all:
            return (
                localized("No recordings yet", locale: locale),
                localized("Start a dictation from the Home page, or import a file.", locale: locale)
            )
        case .dictations:
            return (
                localized("No dictations yet", locale: locale),
                localized("Dictations appear here after you use voice dictation.", locale: locale)
            )
        case .meetings:
            return (
                localized("No meeting recordings", locale: locale),
                localized("Record a meeting from the Home page to see it here.", locale: locale)
            )
        case .media:
            return (
                localized("No media transcriptions", locale: locale),
                localized("Import a file or paste a link to transcribe media.", locale: locale)
            )
        }
    }

    // MARK: - List

    private var transcriptionsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedSections, id: \.key) { group in
                    SectionHeader(
                        title: LibraryDayGrouping.displayTitle(group.key, locale: locale),
                        trailing: "\(group.records.count)",
                        isFirst: group.key == groupedSections.first?.key
                    )
                    .padding(.horizontal, 24)

                    ForEach(group.records) { record in
                        libraryRow(for: record)
                            .task {
                                loadNextPageIfNeeded(currentRecord: record)
                            }
                    }
                }

                Color.clear
                    .frame(height: 32)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func libraryRow(for record: TranscriptionRecord) -> some View {
        let isExpanded = expandedTranscriptionID == record.persistentModelID
        let isSelected = selectedTranscriptionID == record.persistentModelID

        VStack(spacing: 0) {
            if isExpanded {
                LibraryExpandedPlayerCard(
                    record: record,
                    retention: retention,
                    onCopy: { copyRecord(record) },
                    onExport: { format in exportRecord(record, format: format) },
                    onDelete: { pendingDeletionRecord = record }
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                // No selected wash behind the expanded card: per the design the card's
                // own ground fill + border IS the expanded/selected affordance.
            } else {
                collapsedRow(for: record)
                    .background(isSelected ? AppColors.accent.opacity(0.06) : Color.clear)
            }
        }
    }

    private static let rowTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func collapsedRow(for record: TranscriptionRecord) -> some View {
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
                    isExpired: isExpired || (!hasAudio && record.duration > 0 && kind == .voiceRecording),
                    action: playChipAction(for: record, hasAudio: hasAudio)
                )
            },
            action: {
                handleRowTap(record)
            }
        )
    }

    /// Whether this record drills into the detail page (spec §8) instead of the
    /// inline player card: meetings AND imported/linked media — their transcripts
    /// are long-form and swallow the list when expanded inline. Quick dictations
    /// keep the inline card.
    private func opensDetailPage(_ record: TranscriptionRecord) -> Bool {
        switch record.resolvedSourceKind {
        case .manualCapture, .importedFile, .webLink:
            return true
        case .voiceRecording:
            return false
        }
    }

    /// Play chip and row agree: detail-page kinds → detail; dictations with audio → expand.
    private func playChipAction(for record: TranscriptionRecord, hasAudio: Bool) -> (() -> Void)? {
        if opensDetailPage(record) {
            return { openDetail(record) }
        }
        guard hasAudio else { return nil }
        return { toggleExpansion(for: record) }
    }

    private func handleRowTap(_ record: TranscriptionRecord) {
        selectedTranscriptionID = record.persistentModelID

        if opensDetailPage(record) {
            openDetail(record)
            return
        }

        toggleExpansion(for: record)
    }

    private func toggleExpansion(for record: TranscriptionRecord) {
        withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
            if expandedTranscriptionID == record.persistentModelID {
                expandedTranscriptionID = nil
            } else {
                expandedTranscriptionID = record.persistentModelID
            }
        }
    }

    private func openDetail(_ record: TranscriptionRecord) {
        expandedTranscriptionID = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            detailRecord = record
        }
    }

    // MARK: - Detail helpers

    private func assignRecord(_ record: TranscriptionRecord, to folder: MediaFolder) {
        do {
            try historyStore.assign(record: record, to: folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRecordFromFolder(_ record: TranscriptionRecord) {
        do {
            try historyStore.removeFromFolder(record: record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignSpeakerProfile(
        for record: TranscriptionRecord,
        speakerID: String,
        profileID: UUID
    ) {
        do {
            try historyStore.assignSpeakerProfile(
                record: record,
                speakerID: speakerID,
                profileID: profileID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    private func unassignSpeakerProfile(
        for record: TranscriptionRecord,
        speakerID: String
    ) {
        do {
            try historyStore.unassignSpeakerProfile(record: record, speakerID: speakerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAndAssignSpeakerProfile(
        for record: TranscriptionRecord,
        speakerID: String,
        name: String,
        notes: String?
    ) -> Bool {
        do {
            try historyStore.createAndAssignSpeakerProfile(
                record: record,
                speakerID: speakerID,
                displayName: name,
                notes: notes
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func confirmDeletePendingRecord() {
        guard let record = pendingDeletionRecord else { return }
        let deletedID = record.id
        let deletedPersistentID = record.persistentModelID
        pendingDeletionRecord = nil

        do {
            try historyStore.delete(record)
            if detailRecord?.id == deletedID {
                detailRecord = nil
            }
            if expandedTranscriptionID == deletedPersistentID {
                expandedTranscriptionID = nil
            }
            if selectedTranscriptionID == deletedPersistentID {
                selectedTranscriptionID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Copy / Export

    private func copyRecord(_ record: TranscriptionRecord) {
        NotificationCenter.default.post(
            name: .copyTextWithUndo,
            object: nil,
            userInfo: ["text": record.text]
        )
    }

    private func exportRecord(_ record: TranscriptionRecord, format: TranscriptExportFormat) {
        do {
            try TranscriptExportService.presentSavePanel(for: record, format: format)
        } catch TranscriptExportService.ExportError.cancelled {
            // User dismissed the panel.
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Import actions

    /// Pops the transcribe menu below the split button, aligned to its leading
    /// edge (SwiftUI's Menu anchored it to the chevron and drifted right).
    private func presentTranscribeMenu() {
        guard let anchor = transcribeMenuAnchorView else { return }

        let menu = NSMenu()
        if onImportMediaFiles != nil {
            menu.addItem(ClosureMenuItem(
                title: localized("Import Files…", locale: locale),
                systemImage: "folder"
            ) { importFilesViaOpenPanel() })
        }
        if onSubmitMediaLink != nil {
            menu.addItem(ClosureMenuItem(
                title: localized("Paste Link…", locale: locale),
                systemImage: "link"
            ) {
                pasteLinkText = ""
                showPasteLinkSheet = true
            })
        }
        if onImportMediaFiles != nil || onSubmitMediaLink != nil {
            menu.addItem(.separator())
            let diarizationItem = ClosureMenuItem(
                title: localized("Speaker diarization", locale: locale),
                systemImage: "person.2.wave.2"
            ) {
                isSpeakerDiarizationEnabled.toggle()
                if !isSpeakerDiarizationEnabled {
                    expectedSpeakerCount = nil
                }
            }
            diarizationItem.state = isSpeakerDiarizationEnabled ? .on : .off
            menu.addItem(diarizationItem)

            let expectedSpeakersItem = NSMenuItem(
                title: localized("Expected speakers", locale: locale),
                action: nil,
                keyEquivalent: ""
            )
            expectedSpeakersItem.identifier = NSUserInterfaceItemIdentifier("expectedSpeakersMenu")
            expectedSpeakersItem.isEnabled = isSpeakerDiarizationEnabled
            expectedSpeakersItem.submenu = makeExpectedSpeakersSubmenu()
            menu.addItem(expectedSpeakersItem)
        }
        if onStartMeetingCapture != nil {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(
                title: localized("Record Meeting…", locale: locale),
                systemImage: "person.2.wave.2"
            ) {
                showMeetingCaptureOptions = true
            })
        }

        // Non-flipped view coords: (0, 0) is the bottom-left corner, and popUp
        // places the menu's top-left at the given point → just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: anchor)
    }

    private func makeExpectedSpeakersSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let automaticItem = ClosureMenuItem(
            title: localized("Automatic", locale: locale),
            systemImage: nil
        ) {
            expectedSpeakerCount = nil
        }
        automaticItem.state = expectedSpeakerCount == nil ? .on : .off
        automaticItem.identifier = NSUserInterfaceItemIdentifier("expectedSpeakersAutomatic")
        automaticItem.isEnabled = isSpeakerDiarizationEnabled
        submenu.addItem(automaticItem)

        for count in 1...20 {
            let item = ClosureMenuItem(
                title: "\(count)",
                systemImage: nil
            ) {
                expectedSpeakerCount = count
            }
            item.state = expectedSpeakerCount == count ? .on : .off
            item.identifier = NSUserInterfaceItemIdentifier("expectedSpeakersCount-\(count)")
            item.isEnabled = isSpeakerDiarizationEnabled
            submenu.addItem(item)
        }

        return submenu
    }

    private func importFilesViaOpenPanel() {
        guard let onImportMediaFiles else { return }
        let panel = NSOpenPanel()
        panel.title = localized("Import media", locale: locale)
        panel.message = localized("Choose an audio or video file to transcribe", locale: locale)
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie, .video]

        if panel.runModal() == .OK {
            let supported = filterSupportedMediaURLs(panel.urls)
            guard !supported.isEmpty else { return }
            onImportMediaFiles(supported, defaultJobOptions)
        }
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        guard let onImportMediaFiles else { return }
        let supported = filterSupportedMediaURLs(urls)
        guard !supported.isEmpty else { return }
        onImportMediaFiles(supported, defaultJobOptions)
    }

    private func filterSupportedMediaURLs(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                return false
            }
            return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
        }
    }

    private var pasteLinkSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Paste Link…", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("https://…", locale: locale), text: $pasteLinkText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 360)

            HStack {
                Spacer()
                Button(localized("Cancel", locale: locale)) {
                    showPasteLinkSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(localized("Import", locale: locale)) {
                    let trimmed = pasteLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, let onSubmitMediaLink else {
                        showPasteLinkSheet = false
                        return
                    }
                    onSubmitMediaLink(trimmed, defaultJobOptions)
                    showPasteLinkSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pasteLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    // MARK: - Data Loading

    private enum LoadMode {
        case reload
        case refresh(visibleLimit: Int)
    }

    private var currentLoadRequest: HistoryLoadRequest {
        HistoryLoadRequest(
            query: trimmedSearchText,
            filter: selectedFilter.historyFilter,
            sort: selectedSort
        )
    }

    private func reloadTranscriptions() {
        scheduleLoad(mode: .reload, debounce: true)
    }

    private func refreshVisibleTranscriptions() {
        scheduleLoad(
            mode: .refresh(visibleLimit: max(currentOffset, pageSize)),
            debounce: false
        )
    }

    private func scheduleLoad(mode: LoadMode, debounce: Bool) {
        let request = currentLoadRequest
        requestGeneration &+= 1
        let generation = requestGeneration
        activeRequest = request
        loadTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        paginationGeneration &+= 1

        loadTask = Task {
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
            await performLoad(mode: mode, request: request, generation: generation)
        }
    }

    private func performLoad(
        mode: LoadMode,
        request: HistoryLoadRequest,
        generation: UInt
    ) async {
        guard isCurrent(request, generation: generation) else { return }

        do {
            let snapshot = try await historyStore.transcriptionSnapshot(
                query: request.query,
                filter: request.filter,
                sort: request.sort
            )
            guard isCurrent(request, generation: generation) else { return }

            switch mode {
            case .reload:
                transcriptionSnapshot = snapshot
                snapshotRequest = request
                snapshotGeneration = generation
                totalCount = snapshot.count
                totalSpokenDuration = snapshot.spokenDuration
                replaceVisibleRecords([])
                currentOffset = 0
                hasMorePages = snapshot.count > 0
                isLoading = snapshot.count > 0

                guard snapshot.count > 0 else { return }
                let records = try records(
                    for: request,
                    snapshot: snapshot,
                    limit: pageSize,
                    offset: 0
                )
                guard isCurrent(request, generation: generation) else { return }
                applyInitialPage(records, snapshot: snapshot)

            case .refresh(let visibleLimit):
                let records = try records(
                    for: request,
                    snapshot: snapshot,
                    limit: visibleLimit,
                    offset: 0
                )
                guard isCurrent(request, generation: generation) else { return }
                transcriptionSnapshot = snapshot
                snapshotRequest = request
                snapshotGeneration = generation
                totalCount = snapshot.count
                totalSpokenDuration = snapshot.spokenDuration
                replaceVisibleRecords(records)
                currentOffset = records.count
                hasMorePages = records.count < snapshot.count
                isLoading = false
            }
        } catch is CancellationError {
            // A newer generation cancelled this load; leave UI state alone.
            return
        } catch {
            guard isCurrent(request, generation: generation) else { return }
            if case .reload = mode {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func records(
        for request: HistoryLoadRequest,
        snapshot: HistoryStore.TranscriptionSnapshot,
        limit: Int,
        offset: Int
    ) throws -> [TranscriptionRecord] {
        if let searchedPage = snapshot.page(limit: limit, offset: offset) {
            return searchedPage
        }
        return try historyStore.fetchTranscriptions(
            limit: limit,
            offset: offset,
            query: request.query,
            filter: request.filter,
            sort: request.sort
        )
    }

    private func applyInitialPage(
        _ records: [TranscriptionRecord],
        snapshot: HistoryStore.TranscriptionSnapshot
    ) {
        replaceVisibleRecords(records)
        currentOffset = records.count
        hasMorePages = records.count < snapshot.count
        isLoading = false
    }

    /// Single path for visible-record mutations so grouping stays coherent with
    /// the flat list and is never re-derived on selection-only updates.
    private func replaceVisibleRecords(_ records: [TranscriptionRecord]) {
        visibleTranscriptions = records
        groupedSections = LibraryDayGrouping.sections(
            from: records,
            newestFirst: newestFirstGrouping
        )
    }

    private func appendVisibleRecords(_ records: [TranscriptionRecord]) {
        guard !records.isEmpty else { return }
        visibleTranscriptions.append(contentsOf: records)
        groupedSections = LibraryDayGrouping.sections(
            from: visibleTranscriptions,
            newestFirst: newestFirstGrouping
        )
    }

    private func loadNextPage() {
        guard hasMorePages,
              let snapshot = transcriptionSnapshot,
              snapshotRequest == currentLoadRequest,
              snapshotGeneration == requestGeneration else { return }

        let request = currentLoadRequest
        let generation = requestGeneration
        let offset = currentOffset
        paginationTask?.cancel()
        paginationGeneration &+= 1
        let pageGeneration = paginationGeneration

        paginationTask = Task {
            defer {
                if pageGeneration == paginationGeneration {
                    paginationTask = nil
                }
            }

            guard isCurrent(request, generation: generation) else { return }
            do {
                let records = try records(
                    for: request,
                    snapshot: snapshot,
                    limit: pageSize,
                    offset: offset
                )
                guard isCurrent(request, generation: generation),
                      currentOffset == offset else { return }
                appendVisibleRecords(records)
                currentOffset += records.count
                hasMorePages = currentOffset < snapshot.count
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(request, generation: generation) else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadNextPageIfNeeded(currentRecord: TranscriptionRecord) {
        guard let lastRecord = visibleTranscriptions.last,
              lastRecord.id == currentRecord.id,
              hasMorePages else { return }
        loadNextPage()
    }

    private func isCurrent(_ request: HistoryLoadRequest, generation: UInt) -> Bool {
        !Task.isCancelled && HistoryLoadRequest.isCurrent(
            request,
            generation: generation,
            activeRequest: activeRequest,
            activeGeneration: requestGeneration
        )
    }

    private func cancelManagedLoads() {
        requestGeneration &+= 1
        activeRequest = nil
        loadTask?.cancel()
        paginationTask?.cancel()
        loadTask = nil
        paginationTask = nil
        paginationGeneration &+= 1
    }

    // MARK: - Keyboard Selection

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil, detailRecord == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard shouldHandleListKeyEvent(event) else { return event }
            return handleListKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shouldHandleListKeyEvent(_ event: NSEvent) -> Bool {
        guard detailRecord == nil else { return false }
        guard MainWindowController.isMainWindowKey(event.window) else { return false }
        if isSearchFieldFocused { return false }
        if Self.isTextInputFirstResponder(event.window?.firstResponder) {
            return false
        }
        return true
    }

    private static func isTextInputFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSTextField { return true }
        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isSelectable
        }
        if responder is NSText { return true }
        return false
    }

    private func applySearchFocus() {
        MainWindowController.pendingHistorySearchFocus = false
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private func consumePendingSearchFocusIfNeeded() {
        guard MainWindowController.pendingHistorySearchFocus else { return }
        applySearchFocus()
    }

    private func handleListKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Up 126 / Down 125 / Escape 53 / Delete 51 / Forward Delete 117
        switch event.keyCode {
        case 126:
            moveListSelection(delta: -1)
            return nil
        case 125:
            moveListSelection(delta: 1)
            return nil
        case 51, 117:
            requestDeleteForSelection()
            return nil
        case 53:
            return clearOrCollapseSelection() ? nil : event
        case 36:
            // Return — expand or open detail for selection
            if let record = visibleTranscriptions.first(where: {
                $0.persistentModelID == selectedTranscriptionID
            }) {
                handleRowTap(record)
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func moveListSelection(delta: Int) {
        let records = visibleTranscriptions
        let currentIndex = records.firstIndex(where: { $0.persistentModelID == selectedTranscriptionID })
        guard let nextIndex = ListSelectionNavigation.moveIndex(
            current: currentIndex,
            count: records.count,
            delta: delta
        ) else { return }
        withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
            selectedTranscriptionID = records[nextIndex].persistentModelID
        }
    }

    private func requestDeleteForSelection() {
        if let record = visibleTranscriptions.first(where: {
            $0.persistentModelID == selectedTranscriptionID
        }) {
            pendingDeletionRecord = record
        }
    }

    /// Clears expansion / selection. Returns `true` if something changed.
    @discardableResult
    private func clearOrCollapseSelection() -> Bool {
        if expandedTranscriptionID != nil {
            withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
                expandedTranscriptionID = nil
            }
            return true
        }
        guard selectedTranscriptionID != nil else { return false }
        withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
            selectedTranscriptionID = nil
        }
        return true
    }
}

// MARK: - Previews

#Preview("History") {
    HistoryView()
        .modelContainer(PreviewContainer.withSampleData)
}

#Preview("History Empty") {
    HistoryView()
        .modelContainer(PreviewContainer.empty)
}

#Preview("History Dark") {
    HistoryView()
        .modelContainer(PreviewContainer.withSampleData)
        .preferredColorScheme(.dark)
}

// MARK: - Transcribe split-button support

/// Exposes the hosting NSView so the transcribe menu can pop anchored to the
/// split button's own frame rather than SwiftUI Menu's chevron-relative anchor.
private struct TranscribeMenuAnchor: NSViewRepresentable {
    let onReady: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// NSMenuItem that owns its action closure (NSMenuItem.target is weak — the
/// item targets itself, and the menu retains the item).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
