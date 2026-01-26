//
//  HistoryView.swift
//  Pindrop
//
//  History view for embedding in the main window
//  Refactored from HistoryWindow to work as a view component
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var selectedRecord: TranscriptionRecord?
    
    var filteredTranscriptions: [TranscriptionRecord] {
        if searchText.isEmpty {
            return transcriptions
        } else {
            return transcriptions.filter { record in
                record.text.localizedStandardContains(searchText)
            }
        }
    }
    
    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }
    
    /// Group transcriptions by date
    private var groupedTranscriptions: [(String, [TranscriptionRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTranscriptions) { record -> String in
            if calendar.isDateInToday(record.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(record.timestamp) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM d, yyyy"
                return formatter.string(from: record.timestamp)
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
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("History")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(filteredTranscriptions.count) transcriptions")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                exportMenu
            }
            
            // Search bar
            searchBar
        }
        .padding(AppTheme.Spacing.xxl)
        .background(AppColors.contentBackground)
    }
    
    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            
            TextField("Search transcriptions...", text: $searchText)
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
        .background(AppColors.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }
    
    private var exportMenu: some View {
        Menu {
            Button {
                exportToPlainText()
            } label: {
                Label("Export as Plain Text", systemImage: "doc.text")
            }
            
            Button {
                exportToJSON()
            } label: {
                Label("Export as JSON", systemImage: "curlybraces")
            }
            
            Button {
                exportToCSV()
            } label: {
                Label("Export as CSV", systemImage: "tablecells")
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "square.and.arrow.up")
                Text("Export")
            }
            .font(AppTypography.subheadline)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .menuStyle(.borderlessButton)
        .disabled(filteredTranscriptions.isEmpty)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage = errorMessage {
            errorView(errorMessage)
        } else if filteredTranscriptions.isEmpty {
            emptyStateView
        } else {
            transcriptionsList
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
            
            Text("Something went wrong")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button("Dismiss") {
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
            
            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(searchText.isEmpty
                 ? "Start recording to see your transcriptions here"
                 : "Try a different search term")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var transcriptionsList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.xxl, pinnedViews: .sectionHeaders) {
                ForEach(groupedTranscriptions, id: \.0) { dateGroup, records in
                    Section {
                        VStack(spacing: AppTheme.Spacing.md) {
                            ForEach(records) { record in
                                HistoryTranscriptionRow(
                                    record: record,
                                    isSelected: selectedRecord?.id == record.id,
                                    onTap: { selectedRecord = (selectedRecord?.id == record.id) ? nil : record }
                                )
                            }
                        }
                    } header: {
                        dateHeader(dateGroup)
                    }
                }
            }
            .padding(AppTheme.Spacing.xxl)
        }
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
    
    private func exportToPlainText() {
        Task { @MainActor in
            do {
                try historyStore.exportToPlainText(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func exportToJSON() {
        Task { @MainActor in
            do {
                try historyStore.exportToJSON(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func exportToCSV() {
        Task { @MainActor in
            do {
                try historyStore.exportToCSV(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - History Transcription Row

struct HistoryTranscriptionRow: View {
    let record: TranscriptionRecord
    let isSelected: Bool
    let onTap: () -> Void
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
    
    private var formattedDuration: String {
        String(format: "%.1fs", record.duration)
    }
    
    var body: some View {
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
                Text(record.text)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(isSelected ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Metadata row (shown when selected or hovering)
                HStack(spacing: AppTheme.Spacing.lg) {
                    metadataItem(icon: "waveform", text: formattedDuration)
                    metadataItem(icon: "cpu", text: record.modelUsed)
                }
            }
            
            CopyButton(text: record.text)
                .opacity(isSelected ? 1 : 0.6)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(isSelected ? AppColors.accentBackground : AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(isSelected ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
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
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
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
}

// MARK: - Preview

#Preview("History View - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    let context = container.mainContext
    
    let samples = [
        TranscriptionRecord(
            text: "This is a sample transcription that demonstrates how the history view looks with actual content.",
            timestamp: Date(),
            duration: 5.2,
            modelUsed: "tiny.en"
        ),
        TranscriptionRecord(
            text: "Another transcription from earlier today to show grouping.",
            timestamp: Date().addingTimeInterval(-3600),
            duration: 3.8,
            modelUsed: "base.en"
        ),
        TranscriptionRecord(
            text: "Yesterday's transcription to demonstrate date grouping functionality.",
            timestamp: Date().addingTimeInterval(-86400),
            duration: 8.5,
            modelUsed: "small.en"
        ),
        TranscriptionRecord(
            text: "An older transcription from a few days ago.",
            timestamp: Date().addingTimeInterval(-259200),
            duration: 12.1,
            modelUsed: "base.en"
        )
    ]
    
    for sample in samples {
        context.insert(sample)
    }
    
    return HistoryView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.light)
}

#Preview("History View - Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    
    return HistoryView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.light)
}

#Preview("History View - Dark") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    let context = container.mainContext
    
    for i in 0..<5 {
        let record = TranscriptionRecord(
            text: "Sample transcription \(i + 1) with some text content.",
            timestamp: Date().addingTimeInterval(Double(-i * 7200)),
            duration: Double.random(in: 3...15),
            modelUsed: "tiny.en"
        )
        context.insert(record)
    }
    
    return HistoryView()
        .modelContainer(container)
        .frame(width: 800, height: 600)
        .preferredColorScheme(.dark)
}
