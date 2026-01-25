//
//  HistoryStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class HistoryStoreTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var historyStore: HistoryStore!
    
    override func setUp() async throws {
        let schema = Schema([TranscriptionRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        historyStore = HistoryStore(modelContext: modelContext)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        historyStore = nil
    }
    
    func testSaveTranscription() throws {
        try historyStore.save(
            text: "Hello, world!",
            duration: 5.0,
            modelUsed: "tiny"
        )
        
        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Hello, world!")
        XCTAssertEqual(records.first?.duration, 5.0)
        XCTAssertEqual(records.first?.modelUsed, "tiny")
    }
    
    func testFetchTranscriptions() throws {
        try historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        try historyStore.save(text: "Third", duration: 3.0, modelUsed: "small")
        
        let allRecords = try historyStore.fetchAll()
        XCTAssertEqual(allRecords.count, 3)
        XCTAssertEqual(allRecords[0].text, "Third")
        XCTAssertEqual(allRecords[1].text, "Second")
        XCTAssertEqual(allRecords[2].text, "First")
        
        let limitedRecords = try historyStore.fetch(limit: 2)
        XCTAssertEqual(limitedRecords.count, 2)
        XCTAssertEqual(limitedRecords[0].text, "Third")
        XCTAssertEqual(limitedRecords[1].text, "Second")
    }
    
    func testSearchTranscriptions() throws {
        try historyStore.save(text: "The quick brown fox", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "jumps over the lazy dog", duration: 2.0, modelUsed: "base")
        try historyStore.save(text: "Hello world", duration: 3.0, modelUsed: "small")
        
        let results = try historyStore.search(query: "quick")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "The quick brown fox")
        
        let multipleResults = try historyStore.search(query: "the")
        XCTAssertEqual(multipleResults.count, 2)
        
        let noResults = try historyStore.search(query: "nonexistent")
        XCTAssertEqual(noResults.count, 0)
    }
    
    func testDeleteTranscription() throws {
        try historyStore.save(text: "To be deleted", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "To be kept", duration: 2.0, modelUsed: "base")
        
        var records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 2)
        
        let recordToDelete = records.first { $0.text == "To be deleted" }!
        try historyStore.delete(recordToDelete)
        
        records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "To be kept")
    }
    
    func testDeleteAll() throws {
        try historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        try historyStore.save(text: "Third", duration: 3.0, modelUsed: "small")
        
        var records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 3)
        
        try historyStore.deleteAll()
        
        records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 0)
    }
    
    func testTimestampOrdering() async throws {
        try historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        try historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        
        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].text, "Second")
        XCTAssertEqual(records[1].text, "First")
        XCTAssertGreaterThan(records[0].timestamp, records[1].timestamp)
    }
    
    func testUniqueIDs() throws {
        try historyStore.save(text: "First", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "Second", duration: 2.0, modelUsed: "base")
        
        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 2)
        XCTAssertNotEqual(records[0].id, records[1].id)
    }
    
    func testCaseInsensitiveSearch() throws {
        try historyStore.save(text: "Hello World", duration: 1.0, modelUsed: "tiny")
        
        let lowerResults = try historyStore.search(query: "hello")
        XCTAssertEqual(lowerResults.count, 1)
        
        let upperResults = try historyStore.search(query: "WORLD")
        XCTAssertEqual(upperResults.count, 1)
        
        let mixedResults = try historyStore.search(query: "HeLLo WoRLd")
        XCTAssertEqual(mixedResults.count, 1)
    }
    
    // MARK: - Export Tests
    
    func testExportToJSON() throws {
        // Create test records
        try historyStore.save(text: "First transcription", duration: 5.0, modelUsed: "tiny")
        try historyStore.save(text: "Second transcription", duration: 10.0, modelUsed: "base")
        
        let records = try historyStore.fetchAll()
        
        // Create temporary file URL for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_export.json")
        
        // Clean up any existing file
        try? FileManager.default.removeItem(at: testURL)
        
        // Export using internal method (bypassing NSSavePanel for testing)
        let exportRecords = try exportToJSONInternal(records: records, to: testURL)
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
        
        // Read and verify JSON content
        let jsonData = try Data(contentsOf: testURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
        }
        
        let exportData = try decoder.decode(ExportData.self, from: jsonData)
        
        XCTAssertEqual(exportData.totalRecords, 2)
        XCTAssertEqual(exportData.records.count, 2)
        XCTAssertEqual(exportData.records[0].text, "Second transcription")
        XCTAssertEqual(exportData.records[0].duration, 10.0)
        XCTAssertEqual(exportData.records[0].modelUsed, "base")
        XCTAssertEqual(exportData.records[1].text, "First transcription")
        XCTAssertEqual(exportData.records[1].duration, 5.0)
        XCTAssertEqual(exportData.records[1].modelUsed, "tiny")
        
        // Clean up
        try? FileManager.default.removeItem(at: testURL)
    }
    
    func testExportToCSV() throws {
        // Create test records
        try historyStore.save(text: "First transcription", duration: 5.0, modelUsed: "tiny")
        try historyStore.save(text: "Text with \"quotes\" and, commas", duration: 10.0, modelUsed: "base")
        
        let records = try historyStore.fetchAll()
        
        // Create temporary file URL for testing
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_export.csv")
        
        // Clean up any existing file
        try? FileManager.default.removeItem(at: testURL)
        
        // Export using internal method (bypassing NSSavePanel for testing)
        try exportToCSVInternal(records: records, to: testURL)
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
        
        // Read and verify CSV content
        let csvContent = try String(contentsOf: testURL, encoding: .utf8)
        let lines = csvContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].starts(with: "ID,Timestamp,Duration,Model,Text"))
        XCTAssertTrue(lines[1].contains("\"Text with \"\"quotes\"\" and, commas\""))
        XCTAssertTrue(lines[1].contains("10.00"))
        XCTAssertTrue(lines[1].contains("base"))
        XCTAssertTrue(lines[2].contains("\"First transcription\""))
        XCTAssertTrue(lines[2].contains("5.00"))
        XCTAssertTrue(lines[2].contains("tiny"))
        
        // Clean up
        try? FileManager.default.removeItem(at: testURL)
    }
    
    func testExportEmptyRecords() throws {
        // Attempt to export with no records
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_empty.json")
        
        XCTAssertThrowsError(try exportToJSONInternal(records: [], to: testURL)) { error in
            guard let historyError = error as? HistoryStore.HistoryStoreError else {
                XCTFail("Expected HistoryStoreError")
                return
            }
            
            if case .exportFailed(let message) = historyError {
                XCTAssertEqual(message, "No records to export")
            } else {
                XCTFail("Expected exportFailed error")
            }
        }
    }
    
    // MARK: - Test Helpers
    
    private func exportToJSONInternal(records: [TranscriptionRecord], to url: URL) throws {
        guard !records.isEmpty else {
            throw HistoryStore.HistoryStoreError.exportFailed("No records to export")
        }
        
        struct ExportRecord: Codable {
            let id: String
            let text: String
            let timestamp: String
            let duration: TimeInterval
            let modelUsed: String
        }
        
        struct ExportData: Codable {
            let exportDate: String
            let totalRecords: Int
            let records: [ExportRecord]
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        let exportRecords = records.map { record in
            ExportRecord(
                id: record.id.uuidString,
                text: record.text,
                timestamp: dateFormatter.string(from: record.timestamp),
                duration: record.duration,
                modelUsed: record.modelUsed
            )
        }
        
        let exportData = ExportData(
            exportDate: dateFormatter.string(from: Date()),
            totalRecords: records.count,
            records: exportRecords
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: url)
        } catch {
            throw HistoryStore.HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    private func exportToCSVInternal(records: [TranscriptionRecord], to url: URL) throws {
        guard !records.isEmpty else {
            throw HistoryStore.HistoryStoreError.exportFailed("No records to export")
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        var csvContent = "ID,Timestamp,Duration,Model,Text\n"
        
        for record in records {
            let escapedText = record.text
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            
            let row = [
                record.id.uuidString,
                dateFormatter.string(from: record.timestamp),
                String(format: "%.2f", record.duration),
                record.modelUsed,
                "\"\(escapedText)\""
            ].joined(separator: ",")
            
            csvContent += row + "\n"
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HistoryStore.HistoryStoreError.exportFailed(error.localizedDescription)
        }
    }
}
