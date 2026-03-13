//
//  HistoryStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import XCTest
import SQLite3
import SwiftData
@testable import Pindrop

@MainActor
final class HistoryStoreTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var historyStore: HistoryStore!
    
    override func setUp() async throws {
        modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            migrationPlan: TranscriptionRecordMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
        historyStore = HistoryStore(modelContext: modelContext)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        historyStore = nil
    }

    func testDiskBackedMigrationFromV3PreservesExistingTranscriptions() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent("migration.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV3.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            let legacyRecord = TranscriptionRecordSchemaV3.TranscriptionRecord(
                text: "Legacy transcription",
                originalText: nil,
                duration: 4.2,
                modelUsed: "base",
                enhancedWith: nil,
                diarizationSegmentsJSON: nil
            )
            legacyContext.insert(legacyRecord)
            try legacyContext.save()
        }

        let migratedContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            migrationPlan: TranscriptionRecordMigrationPlan.self,
            configurations: configuration
        )
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Legacy transcription")
        XCTAssertEqual(records.first?.resolvedSourceKind, .voiceRecording)
        XCTAssertNil(records.first?.managedMediaPath)

        try? FileManager.default.removeItem(at: directoryURL)
    }

    func testDiskBackedMigrationFromV4LeavesExistingTranscriptionsUnfiled() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent("migration-v4.store")
        let configuration = ModelConfiguration(url: storeURL)

        do {
            let legacyContainer = try ModelContainer(
                for: TranscriptionRecordSchemaV4.TranscriptionRecord.self,
                WordReplacement.self,
                VocabularyWord.self,
                Note.self,
                PromptPreset.self,
                configurations: configuration
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(
                TranscriptionRecordSchemaV4.TranscriptionRecord(
                    text: "Folderless legacy transcription",
                    duration: 7.5,
                    modelUsed: "base",
                    sourceKind: .webLink,
                    sourceDisplayName: "Migration Fixture",
                    originalSourceURL: "https://example.com/video",
                    managedMediaPath: "/tmp/migration-fixture.mp4"
                )
            )
            try legacyContext.save()
        }

        let migratedContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            migrationPlan: TranscriptionRecordMigrationPlan.self,
            configurations: configuration
        )
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Folderless legacy transcription")
        XCTAssertNil(records.first?.folder)

        try? FileManager.default.removeItem(at: directoryURL)
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

    func testSaveAndFetchPreservesDiarizationSegmentsJSON() throws {
        let diarizationJSON = """
        [{"speakerId":"speaker-a","speakerLabel":"Speaker 1","startTime":0,"endTime":1.4,"confidence":0.9,"text":"hello"}]
        """

        try historyStore.save(
            text: "Speaker 1: hello",
            duration: 1.4,
            modelUsed: "tiny",
            diarizationSegmentsJSON: diarizationJSON
        )

        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.diarizationSegmentsJSON, diarizationJSON)
    }

    func testSaveWithoutDiarizationMetadataDefaultsToNil() throws {
        try historyStore.save(
            text: "No diarization metadata",
            duration: 2.0,
            modelUsed: "base"
        )

        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.diarizationSegmentsJSON)
    }

    func testSaveMediaTranscriptionPersistsMediaMetadata() throws {
        let record = try historyStore.save(
            text: "Transcript",
            duration: 12.5,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Example Video",
            originalSourceURL: "https://example.com/watch?v=123",
            managedMediaPath: "/tmp/example-video.mp4",
            thumbnailPath: "/tmp/example-video.png"
        )

        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, record.id)
        XCTAssertEqual(records.first?.resolvedSourceKind, .webLink)
        XCTAssertEqual(records.first?.sourceDisplayName, "Example Video")
        XCTAssertEqual(records.first?.originalSourceURL, "https://example.com/watch?v=123")
        XCTAssertEqual(records.first?.managedMediaPath, "/tmp/example-video.mp4")
        XCTAssertEqual(records.first?.thumbnailPath, "/tmp/example-video.png")
        XCTAssertTrue(records.first?.isMediaTranscription == true)
    }

    func testSaveMediaTranscriptionPersistsSelectedFolder() throws {
        let folder = try historyStore.createFolder(named: "Interviews")
        let record = try historyStore.save(
            text: "Transcript",
            duration: 12.5,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Example Video",
            originalSourceURL: "https://example.com/watch?v=123",
            managedMediaPath: "/tmp/example-video.mp4",
            folderID: folder.id
        )

        XCTAssertEqual(record.folder?.id, folder.id)
        let fetchedRecords = try historyStore.fetchAll()
        XCTAssertEqual(fetchedRecords.first?.folder?.name, "Interviews")
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

    func testFetchVoiceTranscriptionsSupportsOffsetPagination() throws {
        try historyStore.save(text: "First voice", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "Second voice", duration: 2.0, modelUsed: "base")
        try historyStore.save(
            text: "Media item",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .webLink,
            sourceDisplayName: "Example media",
            managedMediaPath: "/tmp/example.mp4"
        )
        try historyStore.save(text: "Third voice", duration: 4.0, modelUsed: "large")

        let firstPage = try historyStore.fetchVoiceTranscriptions(limit: 2)
        let secondPage = try historyStore.fetchVoiceTranscriptions(limit: 2, offset: 2)

        XCTAssertEqual(firstPage.map(\.text), ["Third voice", "Second voice"])
        XCTAssertEqual(secondPage.map(\.text), ["First voice"])
        XCTAssertTrue((firstPage + secondPage).allSatisfy(\.isVoiceTranscription))
    }

    func testCountVoiceTranscriptionsRespectsSearchQuery() throws {
        try historyStore.save(text: "Alpha voice", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(text: "Beta voice", duration: 2.0, modelUsed: "base")
        try historyStore.save(
            text: "Alpha media",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "alpha.mov",
            managedMediaPath: "/tmp/alpha.mov"
        )

        XCTAssertEqual(try historyStore.countVoiceTranscriptions(), 2)
        XCTAssertEqual(try historyStore.countVoiceTranscriptions(query: "Alpha"), 1)
        XCTAssertEqual(try historyStore.countVoiceTranscriptions(query: "Beta"), 1)
        XCTAssertEqual(try historyStore.countVoiceTranscriptions(query: "media"), 0)
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

    func testFetchMediaRecordsOnlyReturnsMediaBackedTranscriptions() throws {
        try historyStore.save(text: "Voice", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(
            text: "Linked media",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Linked media",
            originalSourceURL: "https://example.com/video",
            managedMediaPath: "/tmp/linked.mp4"
        )
        try historyStore.save(
            text: "Imported file",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "clip.mov",
            managedMediaPath: "/tmp/clip.mov"
        )

        let records = try historyStore.fetchMediaRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy(\.isMediaTranscription))
        XCTAssertEqual(records.map(\.resolvedSourceKind), [.importedFile, .webLink])
    }

    func testVoiceAndMediaClassificationMatchesSourceKind() throws {
        try historyStore.save(text: "Voice", duration: 1.0, modelUsed: "tiny")
        try historyStore.save(
            text: "Linked media",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Linked media",
            originalSourceURL: "https://example.com/video",
            managedMediaPath: "/tmp/linked.mp4"
        )
        try historyStore.save(
            text: "Imported file",
            duration: 3.0,
            modelUsed: "small",
            sourceKind: .importedFile,
            sourceDisplayName: "clip.mov",
            managedMediaPath: "/tmp/clip.mov"
        )

        let records = try historyStore.fetchAll()
        XCTAssertEqual(records.count, 3)

        let recordsByText = Dictionary(uniqueKeysWithValues: records.map { ($0.text, $0) })
        XCTAssertTrue(recordsByText["Voice"]?.isVoiceTranscription == true)
        XCTAssertTrue(recordsByText["Voice"]?.isMediaTranscription == false)
        XCTAssertTrue(recordsByText["Linked media"]?.isVoiceTranscription == false)
        XCTAssertTrue(recordsByText["Linked media"]?.isMediaTranscription == true)
        XCTAssertTrue(recordsByText["Imported file"]?.isVoiceTranscription == false)
        XCTAssertTrue(recordsByText["Imported file"]?.isMediaTranscription == true)
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

    func testDeleteRemovesManagedMediaAssets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let mediaURL = tempDirectory.appendingPathComponent("media.mp4")
        let thumbnailURL = tempDirectory.appendingPathComponent("thumbnail.png")
        try Data("media".utf8).write(to: mediaURL)
        try Data("thumb".utf8).write(to: thumbnailURL)

        let record = try historyStore.save(
            text: "Media",
            duration: 8.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "media.mp4",
            managedMediaPath: mediaURL.path,
            thumbnailPath: thumbnailURL.path
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))

        try historyStore.delete(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
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

    func testCreateRenameAndFetchFolders() throws {
        let folder = try historyStore.createFolder(named: " Interviews ")
        XCTAssertEqual(folder.name, "Interviews")

        try historyStore.renameFolder(folder, to: "Customer Interviews")

        let folders = try historyStore.fetchFolders()
        XCTAssertEqual(folders.map(\.name), ["Customer Interviews"])
    }

    func testCreateFolderRejectsDuplicateNamesCaseInsensitively() throws {
        _ = try historyStore.createFolder(named: "Interviews")

        XCTAssertThrowsError(try historyStore.createFolder(named: "interviews")) { error in
            guard let historyError = error as? HistoryStore.HistoryStoreError else {
                return XCTFail("Expected HistoryStoreError")
            }

            if case .saveFailed(let message) = historyError {
                XCTAssertTrue(message.contains("already exists"))
            } else {
                XCTFail("Expected saveFailed duplicate-name error")
            }
        }
    }

    func testDeleteFolderUnassignsTranscriptionsInsteadOfDeletingThem() throws {
        let folder = try historyStore.createFolder(named: "Interviews")
        let record = try historyStore.save(
            text: "Transcript",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Interview",
            managedMediaPath: "/tmp/interview.mp4",
            folderID: folder.id
        )

        try historyStore.deleteFolder(folder)

        let folders = try historyStore.fetchFolders()
        let records = try historyStore.fetchAll()

        XCTAssertTrue(folders.isEmpty)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, record.id)
        XCTAssertNil(records.first?.folder)
    }

    func testAssignAndRemoveTranscriptionFolder() throws {
        let folder = try historyStore.createFolder(named: "Research")
        let record = try historyStore.save(
            text: "Transcript",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Research Call",
            managedMediaPath: "/tmp/research.mp4"
        )

        try historyStore.assign(record: record, to: folder)
        XCTAssertEqual(record.folder?.id, folder.id)

        try historyStore.removeFromFolder(record: record)
        XCTAssertNil(record.folder)
    }

    func testFetchMediaLibrarySearchesTranscriptAndMetadata() throws {
        let folder = try historyStore.createFolder(named: "Research")
        try historyStore.save(
            text: "The product team discussed roadmap risks.",
            originalText: "roadmap risks",
            duration: 5.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Quarterly Research",
            originalSourceURL: "https://example.com/research",
            managedMediaPath: "/tmp/research.mp4",
            folderID: folder.id
        )
        try historyStore.save(
            text: "Another transcript",
            duration: 2.0,
            modelUsed: "base",
            sourceKind: .importedFile,
            sourceDisplayName: "Design Review",
            managedMediaPath: "/tmp/design.mov"
        )

        XCTAssertEqual(try historyStore.fetchMediaLibrary(query: "roadmap").count, 1)
        XCTAssertEqual(try historyStore.fetchMediaLibrary(query: "Quarterly").count, 1)
        XCTAssertEqual(try historyStore.fetchMediaLibrary(query: "example.com/research").count, 1)
        XCTAssertEqual(try historyStore.fetchMediaLibrary(folderID: folder.id, query: "roadmap").count, 1)
        XCTAssertTrue(try historyStore.fetchMediaLibrary(folderID: folder.id, query: "Design").isEmpty)
    }

    func testFetchMediaLibrarySortsByNameAndDate() throws {
        try historyStore.save(
            text: "Zulu",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Zulu Call",
            managedMediaPath: "/tmp/zulu.mp4"
        )
        try historyStore.save(
            text: "Alpha",
            duration: 1.0,
            modelUsed: "base",
            sourceKind: .webLink,
            sourceDisplayName: "Alpha Call",
            managedMediaPath: "/tmp/alpha.mp4"
        )

        let newest = try historyStore.fetchMediaLibrary(sort: .newest)
        let oldest = try historyStore.fetchMediaLibrary(sort: .oldest)
        let ascending = try historyStore.fetchMediaLibrary(sort: .nameAscending)
        let descending = try historyStore.fetchMediaLibrary(sort: .nameDescending)

        XCTAssertEqual(newest.first?.sourceDisplayName, "Alpha Call")
        XCTAssertEqual(oldest.first?.sourceDisplayName, "Zulu Call")
        XCTAssertEqual(ascending.map(\.sourceDisplayName), ["Alpha Call", "Zulu Call"])
        XCTAssertEqual(descending.map(\.sourceDisplayName), ["Zulu Call", "Alpha Call"])
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
        _ = try exportToJSONInternal(records: records, to: testURL)
        
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

    func testRepairServiceRepairsStoreWithV3TablesAndV1Metadata() throws {
        let brokenStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("broken.store")
        let referenceStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("reference-v1.store")
        let repairService = SwiftDataStoreRepairService()

        try createV3Store(at: brokenStoreURL)
        try createV1Store(at: referenceStoreURL)
        try overwriteMetadataAndModelCache(at: brokenStoreURL, using: referenceStoreURL)

        XCTAssertThrowsError(try makeCurrentContainer(at: brokenStoreURL))

        let repairOutcome = try repairService.repairIfNeeded(storeURL: brokenStoreURL)
        XCTAssertTrue(repairOutcome.repaired)
        XCTAssertNotNil(repairOutcome.backupDirectoryURL)

        let repairedContainer = try makeCurrentContainer(at: brokenStoreURL)
        let repairedContext = ModelContext(repairedContainer)
        let records = try repairedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Legacy transcription")
        XCTAssertEqual(records.first?.resolvedSourceKind, .voiceRecording)

        try? FileManager.default.removeItem(at: brokenStoreURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: referenceStoreURL.deletingLastPathComponent())
    }

    func testPrepareStoreLocationMigratesRecognizedLegacyStore() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createV3Store(at: legacyStoreURL)

        try repairService.prepareStoreLocation()

        let migratedStoreURL = repairService.storeURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedStoreURL.path))

        let migratedContainer = try makeCurrentContainer(at: migratedStoreURL)
        let migratedContext = ModelContext(migratedContainer)
        let records = try migratedContext.fetch(FetchDescriptor<TranscriptionRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Legacy transcription")

        try? FileManager.default.removeItem(at: applicationSupportURL)
    }

    func testPrepareStoreLocationIgnoresUnrecognizedLegacyStore() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let repairService = SwiftDataStoreRepairService(
            fileManager: .default,
            applicationSupportRootURL: applicationSupportURL
        )

        try createUnrecognizedStore(at: legacyStoreURL)

        try repairService.prepareStoreLocation()

        XCTAssertFalse(FileManager.default.fileExists(atPath: repairService.storeURL().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyStoreURL.path))

        try? FileManager.default.removeItem(at: applicationSupportURL)
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

    private func createV1Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: TranscriptionRecordSchemaV1.TranscriptionRecordV1.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            configurations: configuration
        )

        let context = ModelContext(container)
        context.insert(
            TranscriptionRecordSchemaV1.TranscriptionRecordV1(
                text: "Original transcription",
                duration: 2.0,
                modelUsed: "tiny"
            )
        )
        try context.save()
    }

    private func createV3Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: TranscriptionRecordSchemaV3.TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            configurations: configuration
        )

        let context = ModelContext(container)
        context.insert(
            TranscriptionRecordSchemaV3.TranscriptionRecord(
                text: "Legacy transcription",
                originalText: "Legacy transcription",
                duration: 4.2,
                modelUsed: "base",
                enhancedWith: nil,
                diarizationSegmentsJSON: nil
            )
        )
        try context.save()
    }

    private func createUnrecognizedStore(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_close(database)
            throw NSError(domain: "HistoryStoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }

        defer { sqlite3_close(database) }

        guard let database else {
            throw NSError(domain: "HistoryStoreTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create SQLite database"])
        }

        let sql = "CREATE TABLE IF NOT EXISTS unrelated_table (id INTEGER PRIMARY KEY)"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }
    }

    private func makeCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: TranscriptionRecord.self,
            MediaFolder.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
            migrationPlan: TranscriptionRecordMigrationPlan.self,
            configurations: configuration
        )
    }

    private func overwriteMetadataAndModelCache(at targetStoreURL: URL, using referenceStoreURL: URL) throws {
        let referenceMetadata = try fetchBlob(
            sql: "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
            at: referenceStoreURL
        )
        let referenceModelCache = try fetchBlob(
            sql: "SELECT Z_CONTENT FROM Z_MODELCACHE LIMIT 1",
            at: referenceStoreURL
        )

        try withDatabase(at: targetStoreURL) { database in
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try updateBlob(
                    sql: "UPDATE Z_METADATA SET Z_PLIST = ? WHERE Z_VERSION = 1",
                    blob: referenceMetadata,
                    on: database
                )
                try execute("DELETE FROM Z_MODELCACHE", on: database)
                try updateBlob(
                    sql: "INSERT INTO Z_MODELCACHE (Z_CONTENT) VALUES (?)",
                    blob: referenceModelCache,
                    on: database
                )
                try execute("COMMIT TRANSACTION", on: database)
            } catch {
                try? execute("ROLLBACK TRANSACTION", on: database)
                throw error
            }
        }
    }

    private func fetchBlob(sql: String, at storeURL: URL) throws -> Data {
        try withDatabase(at: storeURL) { database in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw sqliteError(on: database)
            }

            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw sqliteError(on: database)
            }

            guard let bytes = sqlite3_column_blob(statement, 0) else {
                return Data()
            }

            let count = Int(sqlite3_column_bytes(statement, 0))
            return Data(bytes: bytes, count: count)
        }
    }

    private func updateBlob(sql: String, blob: Data, on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }

        defer { sqlite3_finalize(statement) }

        let bindResult = blob.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(
                statement,
                1,
                rawBuffer.baseAddress,
                Int32(blob.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
        guard bindResult == SQLITE_OK else {
            throw sqliteError(on: database)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(on: database)
        }
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(on: database)
        }
    }

    private func withDatabase<T>(at url: URL, _ work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let error = sqliteError(on: database)
            sqlite3_close(database)
            throw error
        }

        defer { sqlite3_close(database) }

        guard let database else {
            throw sqliteError(on: nil)
        }

        return try work(database)
    }

    private func sqliteError(on database: OpaquePointer?) -> NSError {
        let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "HistoryStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
