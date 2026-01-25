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
    @State private var historyStore: HistoryStore?
    @State private var transcriptions: [TranscriptionRecord] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingExportMenu = false
    
    var filteredTranscriptions: [TranscriptionRecord] {
        if searchText.isEmpty {
            return transcriptions
        } else {
            return transcriptions.filter { record in
                record.text.localizedStandardContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with export button
            HStack {
                Text("Transcription History")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Menu {
                    Button("Export as Plain Text") {
                        exportToPlainText()
                    }
                    Button("Export as JSON") {
                        exportToJSON()
                    }
                    Button("Export as CSV") {
                        exportToCSV()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(filteredTranscriptions.isEmpty)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView("Loading transcriptions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        loadTranscriptions()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTranscriptions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "mic.slash" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                        .foregroundStyle(.secondary)
                    if !searchText.isEmpty {
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredTranscriptions) { record in
                    TranscriptionRow(record: record)
                        .contextMenu {
                            Button("Copy Text") {
                                copyToClipboard(record.text)
                            }
                            Button("Copy with Details") {
                                copyWithDetails(record)
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .searchable(text: $searchText, prompt: "Search transcriptions")
        .onAppear {
            setupHistoryStore()
            loadTranscriptions()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupHistoryStore() {
        if historyStore == nil {
            historyStore = HistoryStore(modelContext: modelContext)
        }
    }
    
    private func loadTranscriptions() {
        guard let historyStore = historyStore else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                transcriptions = try historyStore.fetchAll()
                isLoading = false
            } catch {
                errorMessage = "Failed to load transcriptions: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
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
        guard let historyStore = historyStore else { return }
        
        Task { @MainActor in
            do {
                try historyStore.exportToPlainText(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func exportToJSON() {
        guard let historyStore = historyStore else { return }
        
        Task { @MainActor in
            do {
                try historyStore.exportToJSON(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func exportToCSV() {
        guard let historyStore = historyStore else { return }
        
        Task { @MainActor in
            do {
                try historyStore.exportToCSV(records: filteredTranscriptions)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - TranscriptionRow

struct TranscriptionRow: View {
    let record: TranscriptionRecord
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.timestamp)
    }
    
    private var formattedDuration: String {
        String(format: "%.1fs", record.duration)
    }
    
    private var textPreview: String {
        let maxLength = 150
        if record.text.count > maxLength {
            return String(record.text.prefix(maxLength)) + "..."
        }
        return record.text
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text preview
            Text(textPreview)
                .font(.body)
                .lineLimit(3)
            
            // Metadata
            HStack(spacing: 16) {
                Label(formattedDate, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(formattedDuration, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(record.modelUsed, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
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
        .frame(width: 700, height: 500)
}
