//
//  HistoryWindow.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import SwiftData
import AppKit

struct HistoryWindow: View {
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
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            
            Divider()
            
            contentArea
        }
        .frame(minWidth: 700, minHeight: 500)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search transcriptions")
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcription History")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\(filteredTranscriptions.count) transcriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            exportMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            Label("Export", systemImage: "square.and.arrow.up")
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
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Something went wrong")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Dismiss") {
                self.errorMessage = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "mic.slash" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .font(.headline)
            
            Text(searchText.isEmpty
                 ? "Start recording to see your transcriptions here"
                 : "Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var transcriptionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredTranscriptions) { record in
                    TranscriptionCard(
                        record: record,
                        isSelected: selectedRecord?.id == record.id,
                        onTap: { selectedRecord = record },
                        onCopy: { copyToClipboard(record.text) },
                        onCopyWithDetails: { copyWithDetails(record) }
                    )
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Actions
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func copyWithDetails(_ record: TranscriptionRecord) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let details = """
        Timestamp: \(dateFormatter.string(from: record.timestamp))
        Duration: \(String(format: "%.2f", record.duration))s
        Model: \(record.modelUsed)
        
        \(record.text)
        """
        
        copyToClipboard(details)
    }
    
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

// MARK: - Transcription Card

struct TranscriptionCard: View {
    let record: TranscriptionRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onCopyWithDetails: () -> Void
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
    
    private var formattedDuration: String {
        String(format: "%.1fs", record.duration)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.text)
                .font(.body)
                .lineLimit(isSelected ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                metadataItem(icon: "clock", text: formattedDate)
                metadataItem(icon: "waveform", text: formattedDuration)
                metadataItem(icon: "cpu", text: record.modelUsed)
                
                Spacer()
                
                if isSelected {
                    Button {
                        onCopy()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.spring(duration: 0.2)) {
                onTap()
            }
        }
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            
            Button {
                onCopyWithDetails()
            } label: {
                Label("Copy with Details", systemImage: "doc.on.doc.fill")
            }
        }
    }
    
    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview("History Window") {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
        let context = container.mainContext
        
        let samples = [
            TranscriptionRecord(
                text: "This is a sample transcription that demonstrates how the history window will look with actual content.",
                timestamp: Date(),
                duration: 5.2,
                modelUsed: "tiny.en"
            ),
            TranscriptionRecord(
                text: "Another transcription with different content to show multiple items in the list.",
                timestamp: Date().addingTimeInterval(-3600),
                duration: 3.8,
                modelUsed: "base.en"
            ),
            TranscriptionRecord(
                text: "A longer transcription that will be truncated in the preview to demonstrate how the UI handles longer text content. This should show an ellipsis at the end when it exceeds the maximum preview length.",
                timestamp: Date().addingTimeInterval(-7200),
                duration: 12.5,
                modelUsed: "small.en"
            )
        ]
        
        for sample in samples {
            context.insert(sample)
        }
        
        return container
    }()
    
    HistoryWindow()
        .modelContainer(container)
        .frame(width: 800, height: 600)
}

#Preview("History Window - Empty") {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    }()
    
    HistoryWindow()
        .modelContainer(container)
        .frame(width: 800, height: 600)
}
