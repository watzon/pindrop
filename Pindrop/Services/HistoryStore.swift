//
//  HistoryStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftData
import AppKit

extension Notification.Name {
    static let historyStoreDidChange = Notification.Name("com.pindrop.historyStoreDidChange")
}

@MainActor
@Observable
final class HistoryStore {
    
    enum HistoryStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case searchFailed(String)
        case exportFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save transcription: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch transcriptions: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete transcription: \(message)"
            case .searchFailed(let message):
                return "Failed to search transcriptions: \(message)"
            case .exportFailed(let message):
                return "Failed to export transcriptions: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    @discardableResult
    func save(
        text: String,
        originalText: String? = nil,
        duration: TimeInterval,
        modelUsed: String,
        enhancedWith: String? = nil,
        diarizationSegmentsJSON: String? = nil,
        sourceKind: MediaSourceKind = .voiceRecording,
        sourceDisplayName: String? = nil,
        originalSourceURL: String? = nil,
        managedMediaPath: String? = nil,
        thumbnailPath: String? = nil,
        folderID: UUID? = nil
    ) throws -> TranscriptionRecord {
        let record = TranscriptionRecord(
            text: text,
            originalText: originalText,
            duration: duration,
            modelUsed: modelUsed,
            enhancedWith: enhancedWith,
            diarizationSegmentsJSON: diarizationSegmentsJSON,
            sourceKind: sourceKind,
            sourceDisplayName: sourceDisplayName,
            originalSourceURL: originalSourceURL,
            managedMediaPath: managedMediaPath,
            thumbnailPath: thumbnailPath
        )

        if let folderID,
           let folder = try fetchFolder(id: folderID) {
            record.folder = folder
        }
        
        modelContext.insert(record)
        
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
            return record
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func fetchAll() throws -> [TranscriptionRecord] {
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func fetch(limit: Int) throws -> [TranscriptionRecord] {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchVoiceTranscriptions(
        limit: Int,
        offset: Int = 0,
        query: String = ""
    ) throws -> [TranscriptionRecord] {
        var descriptor = voiceTranscriptionsDescriptor(query: query)
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchAllVoiceTranscriptions(query: String = "") throws -> [TranscriptionRecord] {
        let descriptor = voiceTranscriptionsDescriptor(query: query)

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func countVoiceTranscriptions(query: String = "") throws -> Int {
        let descriptor = voiceTranscriptionsDescriptor(query: query)

        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func fetchMediaRecords(limit: Int? = nil) throws -> [TranscriptionRecord] {
        let records = try fetchAll().filter(\.isMediaTranscription)
        if let limit {
            return Array(records.prefix(limit))
        }
        return records
    }

    func fetchFolders() throws -> [MediaFolder] {
        let descriptor = FetchDescriptor<MediaFolder>()

        do {
            return try modelContext.fetch(descriptor).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }

    func createFolder(named name: String) throws -> MediaFolder {
        let normalizedName = try normalizeFolderName(name)
        guard try !folderNameExists(normalizedName) else {
            throw HistoryStoreError.saveFailed("A folder named \"\(normalizedName)\" already exists.")
        }

        let folder = MediaFolder(name: normalizedName)
        modelContext.insert(folder)

        do {
            try modelContext.save()
            return folder
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func renameFolder(_ folder: MediaFolder, to name: String) throws {
        let normalizedName = try normalizeFolderName(name)
        let existingFolders = try fetchFolders()
        let duplicate = existingFolders.contains {
            $0.id != folder.id && $0.trimmedName.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicate else {
            throw HistoryStoreError.saveFailed("A folder named \"\(normalizedName)\" already exists.")
        }

        folder.name = normalizedName
        folder.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func deleteFolder(_ folder: MediaFolder) throws {
        let records = try fetchMediaRecords().filter { $0.folder?.id == folder.id }
        records.forEach { $0.folder = nil }
        modelContext.delete(folder)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }

    func assign(record: TranscriptionRecord, to folder: MediaFolder) throws {
        record.folder = folder
        folder.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func removeFromFolder(record: TranscriptionRecord) throws {
        record.folder?.updatedAt = Date()
        record.folder = nil

        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }

    func fetchMediaLibrary(
        folderID: UUID? = nil,
        query: String = "",
        sort: MediaLibrarySortMode = .newest
    ) throws -> [TranscriptionRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var records = try fetchMediaRecords()

        if let folderID {
            records = records.filter { $0.folder?.id == folderID }
        }

        if !trimmedQuery.isEmpty {
            records = records.filter { $0.matchesMediaLibrarySearch(trimmedQuery) }
        }

        return sortMediaRecords(records, sort: sort)
    }
    
    func delete(_ record: TranscriptionRecord) throws {
        removeManagedMedia(for: record)
        modelContext.delete(record)
        
        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            let records = try fetchAll()
            records.forEach(removeManagedMedia)
            try modelContext.delete(model: TranscriptionRecord.self)
            try modelContext.save()
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func search(query: String) throws -> [TranscriptionRecord] {
        let predicate = #Predicate<TranscriptionRecord> { record in
            record.text.localizedStandardContains(query)
        }
        
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.searchFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Export Methods
    
    func exportToPlainText(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "transcription_history.txt"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        var content = "Transcription History Export\n"
        content += "Generated: \(dateFormatter.string(from: Date()))\n"
        content += "Total Records: \(recordsToExport.count)\n"
        content += String(repeating: "=", count: 80) + "\n\n"
        
        for (index, record) in recordsToExport.enumerated() {
            content += "Record \(index + 1)\n"
            content += "Timestamp: \(dateFormatter.string(from: record.timestamp))\n"
            content += "Duration: \(String(format: "%.2f", record.duration))s\n"
            content += "Model: \(record.modelUsed)\n"
            if let originalText = record.originalText, originalText != record.text {
                content += "Original:\n\(originalText)\n\n"
            }
            content += "Enhanced:\n\(record.text)\n"
            content += String(repeating: "-", count: 80) + "\n\n"
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    func exportToJSON(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "transcription_history.json"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let originalText: String?
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
            let wasEnhanced: Bool
        }

        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }

        let dateFormatter = ISO8601DateFormatter()

        let exportRecords = recordsToExport.map { record in
            ExportRecord(
                id: record.id.uuidString,
                text: record.text,
                originalText: record.originalText,
                timestamp: dateFormatter.string(from: record.timestamp),
                duration: record.duration,
                modelUsed: record.modelUsed,
                wasEnhanced: record.wasEnhanced
            )
        }
        
        let exportData = ExportData(
            exportDate: dateFormatter.string(from: Date()),
            totalRecords: recordsToExport.count,
            records: exportRecords
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: url)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    func exportToCSV(records: [TranscriptionRecord]? = nil) throws {
        let recordsToExport = try records ?? fetchAll()
        
        guard !recordsToExport.isEmpty else {
            throw HistoryStoreError.exportFailed("No records to export")
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "transcription_history.csv"
        savePanel.title = "Export Transcription History"
        savePanel.message = "Choose a location to save the transcription history"
        
        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else {
            throw HistoryStoreError.exportFailed("Export cancelled")
        }
        
        let dateFormatter = ISO8601DateFormatter()

        var csvContent = "ID,Timestamp,Duration,Model,Original Text,Enhanced Text,Was Enhanced\n"

        for record in recordsToExport {
            let escapedOriginal = (record.originalText ?? "")
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            let escapedText = record.text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            let row = [
                record.id.uuidString,
                dateFormatter.string(from: record.timestamp),
                String(format: "%.2f", record.duration),
                record.modelUsed,
                "\"\(escapedOriginal)\"",
                "\"\(escapedText)\"",
                record.wasEnhanced ? "true" : "false"
            ].joined(separator: ",")

            csvContent += row + "\n"
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }

    private func removeManagedMedia(for record: TranscriptionRecord) {
        let fileManager = FileManager.default
        let candidatePaths = [record.managedMediaPath, record.thumbnailPath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parentDirectories = Set<String>()
        for path in candidatePaths {
            do {
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
                }
                parentDirectories.insert((path as NSString).deletingLastPathComponent)
            } catch {
                Log.app.warning("Failed to remove managed media asset at \(path): \(error.localizedDescription)")
            }
        }

        for directory in parentDirectories where !directory.isEmpty {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory)
                if contents.isEmpty {
                    try fileManager.removeItem(atPath: directory)
                }
            } catch {
                Log.app.debug("Skipping managed media directory cleanup for \(directory): \(error.localizedDescription)")
            }
        }
    }

    private func fetchFolder(id: UUID) throws -> MediaFolder? {
        let folders = try fetchFolders()
        return folders.first { $0.id == id }
    }

    private func folderNameExists(_ name: String) throws -> Bool {
        let folders = try fetchFolders()
        return folders.contains {
            $0.trimmedName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func normalizeFolderName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HistoryStoreError.saveFailed("Folder name cannot be empty.")
        }
        return trimmedName
    }

    private func voiceTranscriptionsDescriptor(query: String) -> FetchDescriptor<TranscriptionRecord> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceRawValue = MediaSourceKind.voiceRecording.rawValue
        let sortDescriptors = [SortDescriptor<TranscriptionRecord>(\.timestamp, order: .reverse)]

        if trimmedQuery.isEmpty {
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        }

        let predicate = #Predicate<TranscriptionRecord> { record in
            (record.sourceKindRawValue == nil || record.sourceKindRawValue == voiceRawValue)
                && record.text.localizedStandardContains(trimmedQuery)
        }
        return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
    }

    private func sortMediaRecords(
        _ records: [TranscriptionRecord],
        sort: MediaLibrarySortMode
    ) -> [TranscriptionRecord] {
        switch sort {
        case .newest:
            return records.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return records.sorted { $0.timestamp < $1.timestamp }
        case .nameAscending:
            return records.sorted {
                $0.mediaLibrarySortName.localizedStandardCompare($1.mediaLibrarySortName) == .orderedAscending
            }
        case .nameDescending:
            return records.sorted {
                $0.mediaLibrarySortName.localizedStandardCompare($1.mediaLibrarySortName) == .orderedDescending
            }
        }
    }
}
