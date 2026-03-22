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
    private static let topListPadding: CGFloat = 12
    private static let pageSize = 50
    private static let listVerticalPadding: CGFloat = 20
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
    
    @Environment(\.locale) private var locale

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var selectedRecord: TranscriptionRecord?
    @State private var visibleTranscriptions: [TranscriptionRecord] = []
    @State private var totalTranscriptionsCount = 0
    @State private var nextFetchOffset = 0
    @State private var isLoadingPage = false
    @State private var hasLoadedInitialPage = false
    @State private var hasMorePages = true

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }
    
    /// Group transcriptions by date
    private var groupedTranscriptions: [(String, [TranscriptionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTranscriptions) { record -> String in
            if calendar.isDateInToday(record.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(record.timestamp) {
                return "Yesterday"
            } else {
                return Self.dayFormatter.string(from: record.timestamp)
            }
        }
        
        // Sort by most recent date first
        return grouped.sorted { first, second in
            if first.key == "Today" { return true }
            if second.key == "Today" { return false }
            if first.key == "Yesterday" { return true }
            if second.key == "Yesterday" { return false }
            return first.value.first?.timestamp ?? Date() > second.value.first?.timestamp ?? Date()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and export
            headerSection
            
            // Content
            contentArea
        }
        .background(AppColors.contentBackground)
        .task(id: trimmedSearchText) {
            await reloadTranscriptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            Task { @MainActor in
                await refreshVisibleTranscriptions()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(localized("History", locale: locale))
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(totalTranscriptionsCount) \(localized("transcriptions", locale: locale))")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                exportMenu
            }
            
            // Search bar
            searchBar
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xxl)
        .padding(.top, AppTheme.Window.mainContentTopInset)
        .background(AppColors.contentBackground)
    }
    
    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            
            TextField(localized("Search transcriptions...", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
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
    
    private var exportMenu: some View {
        Menu {
            Button {
                exportToPlainText()
            } label: {
                Label(localized("Export as Plain Text", locale: locale), systemImage: "doc.text")
            }
            
            Button {
                exportToJSON()
            } label: {
                Label(localized("Export as JSON", locale: locale), systemImage: "curlybraces")
            }
            
            Button {
                exportToCSV()
            } label: {
                Label(localized("Export as CSV", locale: locale), systemImage: "tablecells")
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "square.and.arrow.up")
                Text(localized("Export", locale: locale))
            }
            .font(AppTypography.subheadline)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .menuStyle(.borderlessButton)
        .disabled(totalTranscriptionsCount == 0)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage = errorMessage {
            errorView(errorMessage)
        } else if !hasLoadedInitialPage {
            loadingStateView
        } else if totalTranscriptionsCount == 0 {
            emptyStateView
        } else {
            transcriptionsList
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)

            Text(localized("Loading history...", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
            
            Text(localized("Something went wrong", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(localized("Dismiss", locale: locale)) {
                self.errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: searchText.isEmpty ? "waveform.badge.mic" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(searchText.isEmpty
                 ? localized("No transcriptions yet", locale: locale)
                 : localized("No results found", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(searchText.isEmpty
                 ? localized("Start recording to see your transcriptions here", locale: locale)
                 : localized("Try a different search term", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var transcriptionsList: some View {
        List {
            listTopInsetRow

            ForEach(Array(groupedTranscriptions.enumerated()), id: \.element.0) { index, group in
                let dateGroup = group.0
                let records = group.1

                if index > 0 {
                    sectionSpacerRow
                }

                Section {
                    ForEach(records) { record in
                        HistoryTranscriptionRow(
                            record: record,
                            isSelected: selectedRecord?.id == record.id,
                            onTap: { selectedRecord = (selectedRecord?.id == record.id) ? nil : record }
                        )
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                        .padding(.bottom, AppTheme.Spacing.md)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            Task { @MainActor in
                                await loadNextPageIfNeeded(currentRecord: record)
                            }
                        }
                    }
                } header: {
                    dateHeader(dateGroup)
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                }
            }

            if isLoadingPage && hasLoadedInitialPage && !visibleTranscriptions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.md)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            listBottomInsetRow
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(AppColors.contentBackground)
    }

    private var listTopInsetRow: some View {
        Color.clear
            .frame(height: Self.topListPadding)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var sectionSpacerRow: some View {
        Color.clear
            .frame(height: AppTheme.Spacing.lg)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var listBottomInsetRow: some View {
        Color.clear
            .frame(height: Self.listVerticalPadding)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
    
    private func dateHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.5)
            
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.contentBackground)
    }
    
    // MARK: - Actions

    @MainActor
    private func reloadTranscriptions() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            errorMessage = nil
            selectedRecord = nil
            visibleTranscriptions = []
            totalTranscriptionsCount = 0
            nextFetchOffset = 0
            hasMorePages = true
            hasLoadedInitialPage = false

            totalTranscriptionsCount = try historyStore.countVoiceTranscriptions(query: trimmedSearchText)
            hasMorePages = totalTranscriptionsCount > 0

            guard totalTranscriptionsCount > 0 else {
                hasLoadedInitialPage = true
                isLoadingPage = false
                return
            }

            await loadNextPage()
            hasLoadedInitialPage = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = localized("Failed to load history: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            isLoadingPage = false
            hasLoadedInitialPage = true
            hasMorePages = false
        }
    }

    @MainActor
    private func loadNextPageIfNeeded(currentRecord: TranscriptionRecord) async {
        guard currentRecord.id == visibleTranscriptions.last?.id else { return }
        await loadNextPage()
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoadingPage, hasMorePages else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = try historyStore.fetchVoiceTranscriptions(
                limit: Self.pageSize,
                offset: nextFetchOffset,
                query: trimmedSearchText
            )

            visibleTranscriptions.append(contentsOf: page)
            nextFetchOffset += page.count
            hasMorePages = nextFetchOffset < totalTranscriptionsCount && !page.isEmpty
        } catch {
            errorMessage = localized("Failed to load history: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            hasMorePages = false
        }
    }

    @MainActor
    private func refreshVisibleTranscriptions() async {
        guard hasLoadedInitialPage else { return }

        do {
            let visibleCount = max(visibleTranscriptions.count, Self.pageSize)
            totalTranscriptionsCount = try historyStore.countVoiceTranscriptions(query: trimmedSearchText)

            guard totalTranscriptionsCount > 0 else {
                visibleTranscriptions = []
                nextFetchOffset = 0
                hasMorePages = false
                selectedRecord = nil
                return
            }

            let refreshedRecords = try historyStore.fetchVoiceTranscriptions(
                limit: visibleCount,
                query: trimmedSearchText
            )

            visibleTranscriptions = refreshedRecords
            nextFetchOffset = refreshedRecords.count
            hasMorePages = nextFetchOffset < totalTranscriptionsCount

            if let selectedRecord,
               !refreshedRecords.contains(where: { $0.id == selectedRecord.id }) {
                self.selectedRecord = nil
            }
        } catch {
            errorMessage = localized("Failed to load history: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
    
    private func exportToPlainText() {
        Task { @MainActor in
            do {
                let records = try historyStore.fetchAllVoiceTranscriptions(query: trimmedSearchText)
                try historyStore.exportToPlainText(records: records)
            } catch {
                errorMessage = localized("Export failed: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            }
        }
    }
    
    private func exportToJSON() {
        Task { @MainActor in
            do {
                let records = try historyStore.fetchAllVoiceTranscriptions(query: trimmedSearchText)
                try historyStore.exportToJSON(records: records)
            } catch {
                errorMessage = localized("Export failed: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            }
        }
    }
    
    private func exportToCSV() {
        Task { @MainActor in
            do {
                let records = try historyStore.fetchAllVoiceTranscriptions(query: trimmedSearchText)
                try historyStore.exportToCSV(records: records)
            } catch {
                errorMessage = localized("Export failed: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            }
        }
    }
}

// MARK: - History Transcription Row

struct HistoryTranscriptionRow: View {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    let record: TranscriptionRecord
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @State private var isHovered = false
    @State private var showingSaveSuccess = false

    private var cardBackground: Color {
        if isSelected {
            return AppColors.accentBackground
        }

        return isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground
    }

    private var cardBorder: Color {
        if isSelected {
            return AppColors.accent.opacity(0.3)
        }

        return isHovered ? AppColors.border.opacity(0.9) : AppColors.border
    }

    private var timeString: String {
        Self.timeFormatter.string(from: record.timestamp)
    }

    private var formattedDuration: String {
        String(format: "%.1fs", record.duration)
    }

    private var hasOriginalText: Bool {
        record.enhancedWith != nil
    }
    
    private var notesStore: NotesStore {
        NotesStore(modelContext: modelContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row content
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                // Time column
                Text(timeString)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 60, alignment: .leading)

                // Accent bar
                Rectangle()
                    .fill(isSelected ? AppColors.accent : AppColors.border)
                    .frame(width: 3)
                    .clipShape(Capsule())

                // Content
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    // Enhanced text (primary)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            if hasOriginalText {
                                Text(localized("Enhanced", locale: locale))
                                    .font(AppTypography.tiny)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppColors.accent)
                            }

                            Text(record.text)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        CopyButton(text: record.text)
                            .opacity(isSelected ? 1 : (isHovered ? 0.85 : 0.6))
                    }

                    // Original text (shown when expanded)
                    if isSelected, let originalText = record.originalText {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Divider()
                                .padding(.vertical, AppTheme.Spacing.sm)

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(localized("Original", locale: locale))
                                        .font(AppTypography.tiny)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppColors.textSecondary)

                                    Text(originalText)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                CopyButton(text: originalText)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Metadata row
                    HStack(spacing: AppTheme.Spacing.lg) {
                        metadataItem(icon: "waveform", text: formattedDuration)
                        metadataItem(icon: "cpu", text: record.modelUsed)

                        if let enhancedWith = record.enhancedWith {
                            metadataItem(icon: "sparkles", text: localized("via %@", locale: locale).replacingOccurrences(of: "%@", with: enhancedWith))
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(cardBackground)
            )
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md),
                style: cardBorder
            )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(AppTheme.Animation.fast) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(AppTheme.Animation.fast) {
                onTap()
            }
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
            } label: {
                Label(localized("Copy Enhanced", locale: locale), systemImage: "doc.on.doc")
            }

            if let originalText = record.originalText {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(originalText, forType: .string)
                } label: {
                    Label(localized("Copy Original", locale: locale), systemImage: "doc.on.doc")
                }
            }
            
            Divider()
            
            Button {
                saveAsNote()
            } label: {
                Label(localized("Save as Note", locale: locale), systemImage: "note.text")
            }
        }
        .overlay(
            Group {
                if showingSaveSuccess {
                    successToast
                }
            }
        )
    }

    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppTypography.tiny)
        }
        .foregroundStyle(AppColors.textTertiary)
    }
    
    private var successToast: some View {
        VStack {
            Spacer()
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                Text(localized("Saved as Note", locale: locale))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppColors.accent)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .transition(.opacity.combined(with: .scale))
    }
    
    
    private func saveAsNote() {
        Task {
            // Generate title from first 50 chars of transcription
            let title: String
            let trimmedText = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.count > 50 {
                title = String(trimmedText.prefix(50)) + "..."
            } else if trimmedText.isEmpty {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                title = "Note from \(formatter.string(from: record.timestamp))"
            } else {
                title = trimmedText
            }
            
            // Use enhanced text if available, otherwise original
            let content = record.text
            
            do {
                // Check if AI Enhancement is enabled for metadata generation
                let settingsStore = SettingsStore()
                let generateMetadata = settingsStore.aiEnhancementEnabled
                
                try await notesStore.create(
                    title: title,
                    content: content,
                    tags: [],
                    sourceTranscriptionID: record.id,
                    generateMetadata: generateMetadata
                )
                
                // Show success feedback
                await MainActor.run {
                    withAnimation(AppTheme.Animation.fast) {
                        showingSaveSuccess = true
                    }
                }
                
                // Hide after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    withAnimation(AppTheme.Animation.fast) {
                        showingSaveSuccess = false
                    }
                }
            } catch {
                Log.ui.error("Failed to save transcription as note: \(error)")
            }
        }
    }
}

#Preview("History View - With Data") {
    HistoryView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.light)
}

#Preview("History View - Empty") {
    HistoryView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.light)
}

#Preview("History View - Dark") {
    HistoryView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.dark)
}
