//
//  HistoryView.swift
//  Pindrop
//
//  History view for embedding in the main window
//  Refactored from HistoryWindow to work as a view component
//

import SwiftUI
import SwiftData
import Foundation

struct HistoryView: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedFilter: HistoryStore.HistoryFilter = .all
    @State private var errorMessage: String?
    @State private var selectedTranscriptionID: PersistentIdentifier?
    @State private var detailRecord: TranscriptionRecord?
    @State private var pendingDeletionRecord: TranscriptionRecord?
    @State private var isLoading = true
    @State private var visibleTranscriptions: [TranscriptionRecord] = []
    @State private var totalCount: Int = 0
    @State private var hasMorePages = true
    @State private var currentOffset = 0
    @State private var reloadDebounceTask: Task<Void, Never>?
    @State private var filterCounts: [HistoryStore.HistoryFilter: Int] = [:]
    @State private var hasDismissedHotkeyReminder = false
    @State private var visibleNotes: [NoteSchema.Note] = []
    @State private var pendingDeletionNote: NoteSchema.Note?

    @Query private var mediaFolders: [MediaFolder]
    @Query(sort: \NoteSchema.Note.updatedAt, order: .reverse) private var allNotes: [NoteSchema.Note]

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let pageSize = 50

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }

    private var headerSubtitleText: String {
        if selectedFilter == .notes {
            let count = filteredNotes.count
            return count == 1
                ? localized("1 note", locale: locale)
                : "\(count) \(localized("notes", locale: locale))"
        }
        return totalCount == 1
            ? localized("1 transcription", locale: locale)
            : "\(totalCount) \(localized("transcriptions", locale: locale))"
    }

    private var filteredNotes: [NoteSchema.Note] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return allNotes }
        return allNotes.filter { note in
            note.title.localizedStandardContains(query)
                || note.content.localizedStandardContains(query)
                || note.tags.contains { $0.localizedStandardContains(query) }
        }
    }

    // MARK: - Grouping

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var groupedTranscriptions: [(key: String, records: [TranscriptionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTranscriptions) { record -> String in
            if calendar.isDateInToday(record.timestamp) { return "Today" }
            if calendar.isDateInYesterday(record.timestamp) { return "Yesterday" }
            return Self.dayFormatter.string(from: record.timestamp)
        }

        let order: [String] = ["Today", "Yesterday"]
        return grouped.sorted { a, b in
            let aIndex = order.firstIndex(of: a.key) ?? Int.max
            let bIndex = order.firstIndex(of: b.key) ?? Int.max
            if aIndex != bIndex { return aIndex < bIndex }
            let aDate = a.value.first?.timestamp ?? .distantPast
            let bDate = b.value.first?.timestamp ?? .distantPast
            return aDate > bDate
        }.map { (key: $0.key, records: $0.value) }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let record = detailRecord, record.isMediaTranscription {
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
                    onRenameSpeakers: { labelsBySpeakerID in
                        renameSpeakerLabels(for: record, labelsBySpeakerID: labelsBySpeakerID)
                    },
                    onDelete: { pendingDeletionRecord = record }
                )
                .background(AppColors.contentBackground)
            } else {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                        .padding(.bottom, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Window.mainContentTopInset)
                        .background(AppColors.contentBackground)

                    contentArea
                        .background(AppColors.contentBackground)
                }
                .background(AppColors.contentBackground)
            }
        }
        .task(id: "\(trimmedSearchText)_\(selectedFilter)") {
            await reloadTranscriptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            Task { await refreshVisibleTranscriptions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHistoryRecord)) { notification in
            guard let idString = notification.userInfo?["recordID"] as? String,
                  let id = UUID(uuidString: idString),
                  let record = try? historyStore.fetchRecord(with: id),
                  record.isMediaTranscription else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                detailRecord = record
            }
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
        .confirmationDialog(
            localized("Delete note?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionNote != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletionNote = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                if let note = pendingDeletionNote {
                    deleteNote(note)
                }
                pendingDeletionNote = nil
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                pendingDeletionNote = nil
            }
        } message: {
            Text(localized("This will permanently remove this note.", locale: locale))
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

    private func renameSpeakerLabels(for record: TranscriptionRecord, labelsBySpeakerID: [String: String]) {
        do {
            try historyStore.updateSpeakerLabels(record: record, labelsBySpeakerID: labelsBySpeakerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDeletePendingRecord() {
        guard let record = pendingDeletionRecord else { return }
        let deletedID = record.id
        pendingDeletionRecord = nil

        do {
            try historyStore.delete(record)
            if detailRecord?.id == deletedID {
                detailRecord = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            // Title row
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(localized("History", locale: locale))
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(headerSubtitleText)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: AppTheme.Spacing.lg)

                exportMenu
            }

            // Filter chips
            filterChips

            // Search bar
            searchBar
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            filterChip(.all, label: localized("All", locale: locale), icon: "tray.full.fill")
            filterChip(.voice, label: localized("Voice", locale: locale), icon: "mic.fill")
            filterChip(.notes, label: localized("Notes", locale: locale), icon: "note.text")
            filterChip(.meetings, label: localized("Meetings", locale: locale), icon: "person.2.fill")
            filterChip(.media, label: localized("Media", locale: locale), icon: "headphones")

            Spacer()
        }
    }

    private func filterChip(
        _ filter: HistoryStore.HistoryFilter,
        label: String,
        icon: String
    ) -> some View {
        let isSelected = selectedFilter == filter
        let count = filterCounts[filter] ?? 0

        return Button {
            withAnimation(AppTheme.Animation.fast) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))

                Text(label)
                    .font(AppTypography.caption)

                if count > 0 {
                    Text("\(count)")
                        .font(AppTypography.tiny)
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AppColors.accent.opacity(0.15) : AppColors.mutedSurface)
                        )
                }
            }
            .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppColors.accentBackground : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentTransition(.interpolate)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            TextField(localized("Search transcriptions…", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous),
            style: AppColors.border
        )
    }

    // MARK: - Export Menu

    private var exportMenu: some View {
        Menu {
            Button {
                exportAll(format: "plain")
            } label: {
                Label(localized("Export as Plain Text", locale: locale), systemImage: "doc.plaintext")
            }

            Button {
                exportAll(format: "json")
            } label: {
                Label(localized("Export as JSON", locale: locale), systemImage: "curlybraces")
            }

            Button {
                exportAll(format: "csv")
            } label: {
                Label(localized("Export as CSV", locale: locale), systemImage: "tablecells")
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                Text(localized("Export", locale: locale))
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.surfaceBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if selectedFilter == .notes {
            if filteredNotes.isEmpty {
                emptyView
            } else {
                notesList
            }
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
        let (icon, title, subtitle) = emptyStateContent

        return VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text(subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, AppTheme.Spacing.huge)
    }

    private var emptyStateContent: (icon: String, title: String, subtitle: String) {
        if !trimmedSearchText.isEmpty {
            return (
                "magnifyingglass",
                localized("No results", locale: locale),
                localized("Try a different search term or filter.", locale: locale)
            )
        }

        switch selectedFilter {
        case .all:
            return (
                "waveform.badge.mic",
                localized("No transcriptions yet", locale: locale),
                localized("Start a transcription from the Home page, or import a file.", locale: locale)
            )
        case .voice:
            return (
                "mic.slash.fill",
                localized("No voice transcriptions", locale: locale),
                localized("Voice transcriptions appear here after you use dictation.", locale: locale)
            )
        case .meetings:
            return (
                "person.2.slash.fill",
                localized("No meeting recordings", locale: locale),
                localized("Record a meeting from the Home page to see it here.", locale: locale)
            )
        case .media:
            return (
                "headphones",
                localized("No media transcriptions", locale: locale),
                localized("Import a file or paste a link in the Transcribe section.", locale: locale)
            )
        case .notes:
            return (
                "note.text",
                localized("No notes yet", locale: locale),
                localized("Record a note from the Home page — dictation enhanced into a note.", locale: locale)
            )
        }
    }

    // MARK: - Transcriptions List

    private var transcriptionsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(groupedTranscriptions, id: \.key) { group in
                    dateHeader(group.key)
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xs)

                    ForEach(group.records) { record in
                        TranscriptionHistoryRow(
                            record: record,
                            isSelected: selectedTranscriptionID == record.persistentModelID,
                            timestampStyle: .absolute,
                            onTap: {
                                if record.isMediaTranscription {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        detailRecord = record
                                    }
                                } else {
                                    withAnimation(AppTheme.Animation.fast) {
                                        if selectedTranscriptionID == record.persistentModelID {
                                            selectedTranscriptionID = nil
                                        } else {
                                            selectedTranscriptionID = record.persistentModelID
                                        }
                                    }
                                }
                            },
                            onSaveAsNote: { saveAsNote(record: record) }
                        )
                        .task {
                            loadNextPageIfNeeded(currentRecord: record)
                        }
                    }
                }

                // Bottom padding
                Color.clear
                    .frame(height: AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
        }
    }

    // MARK: - Notes List

    private var groupedNotes: [(key: String, notes: [NoteSchema.Note])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotes) { note -> String in
            if calendar.isDateInToday(note.updatedAt) { return "Today" }
            if calendar.isDateInYesterday(note.updatedAt) { return "Yesterday" }
            return Self.dayFormatter.string(from: note.updatedAt)
        }
        let order: [String] = ["Today", "Yesterday"]
        return grouped.sorted { a, b in
            let aIndex = order.firstIndex(of: a.key) ?? Int.max
            let bIndex = order.firstIndex(of: b.key) ?? Int.max
            if aIndex != bIndex { return aIndex < bIndex }
            let aDate = a.value.first?.updatedAt ?? .distantPast
            let bDate = b.value.first?.updatedAt ?? .distantPast
            return aDate > bDate
        }.map { (key: $0.key, notes: $0.value) }
    }

    private var notesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(groupedNotes, id: \.key) { group in
                    dateHeader(group.key)
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xs)

                    ForEach(group.notes) { note in
                        NoteHistoryRow(
                            note: note,
                            onTap: { openNoteInEditor(note) },
                            onDelete: { pendingDeletionNote = note },
                            onTogglePin: { togglePin(note) }
                        )
                    }
                }

                Color.clear.frame(height: AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
        }
    }

    private func openNoteInEditor(_ note: NoteSchema.Note) {
        let controller = NoteEditorWindowController()
        controller.setModelContainer(modelContext.container)
        controller.show(note: note, isNewNote: false)
    }

    private func togglePin(_ note: NoteSchema.Note) {
        let store = NotesStore(modelContext: modelContext)
        do {
            try store.togglePin(note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ note: NoteSchema.Note) {
        let store = NotesStore(modelContext: modelContext)
        do {
            try store.delete(note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dateHeader(_ title: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
        }
    }

    // MARK: - Data Loading

    private func reloadTranscriptions() async {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch { return }

            do {
                let count = try historyStore.countTranscriptions(
                    query: trimmedSearchText,
                    filter: selectedFilter
                )

                await MainActor.run {
                    totalCount = count
                    visibleTranscriptions = []
                    currentOffset = 0
                    hasMorePages = true
                    isLoading = count > 0
                }

                if count > 0 {
                    await loadNextPage()
                } else {
                    await MainActor.run { isLoading = false }
                }

                // Refresh filter counts in parallel
                await refreshFilterCounts()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
        await reloadDebounceTask?.value
    }

    private func loadNextPage() async {
        guard hasMorePages else { return }

        do {
            let records = try historyStore.fetchTranscriptions(
                limit: pageSize,
                offset: currentOffset,
                query: trimmedSearchText,
                filter: selectedFilter
            )

            await MainActor.run {
                visibleTranscriptions.append(contentsOf: records)
                currentOffset += records.count
                hasMorePages = records.count == pageSize
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadNextPageIfNeeded(currentRecord: TranscriptionRecord) {
        guard let lastRecord = visibleTranscriptions.last,
              lastRecord.id == currentRecord.id,
              hasMorePages else { return }
        Task { await loadNextPage() }
    }

    private func refreshVisibleTranscriptions() async {
        do {
            let count = try historyStore.countTranscriptions(
                query: trimmedSearchText,
                filter: selectedFilter
            )

            let records = try historyStore.fetchTranscriptions(
                limit: max(currentOffset, pageSize),
                offset: 0,
                query: trimmedSearchText,
                filter: selectedFilter
            )

            await MainActor.run {
                totalCount = count
                visibleTranscriptions = records
                currentOffset = records.count
                hasMorePages = records.count < count
            }

            await refreshFilterCounts()
        } catch {
            // Silently refresh; errors here are non-critical
        }
    }

    private func refreshFilterCounts() async {
        do {
            let allCount = try historyStore.countTranscriptions(query: "", filter: .all)
            let voiceCount = try historyStore.countTranscriptions(query: "", filter: .voice)
            let meetingsCount = try historyStore.countTranscriptions(query: "", filter: .meetings)
            let mediaCount = try historyStore.countTranscriptions(query: "", filter: .media)
            let notesCount = allNotes.count

            await MainActor.run {
                filterCounts = [
                    .all: allCount,
                    .voice: voiceCount,
                    .meetings: meetingsCount,
                    .media: mediaCount,
                    .notes: notesCount
                ]
            }
        } catch {
            // Non-critical
        }
    }

    // MARK: - Save as Note

    private func saveAsNote(record: TranscriptionRecord) {
        let notesStore = NotesStore(modelContext: modelContext)
        Task { @MainActor in
            let titlePrefix = String(record.text.prefix(50))
            let title = titlePrefix.count < record.text.count ? "\(titlePrefix)…" : titlePrefix

            var noteContent = record.text
            if let original = record.originalText, !original.isEmpty, original != record.text {
                noteContent += "\n\n---\n\nOriginal:\n\(original)"
            }
            if let enhancedWith = record.enhancedWith {
                noteContent += "\n\n---\n\nEnhanced with: \(enhancedWith)"
            }
            try? await notesStore.create(title: title, content: noteContent)
        }
    }

    // MARK: - Export

    private func exportAll(format: String) {
        do {
            let records = try historyStore.fetchAllTranscriptions(
                query: trimmedSearchText,
                filter: selectedFilter
            )
            guard !records.isEmpty else { return }

            switch format {
            case "plain":
                try historyStore.exportToPlainText(records: records)
            case "json":
                try historyStore.exportToJSON(records: records)
            case "csv":
                try historyStore.exportToCSV(records: records)
            default:
                break
            }
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
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
