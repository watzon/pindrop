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
}
