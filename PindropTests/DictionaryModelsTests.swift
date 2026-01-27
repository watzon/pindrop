//
//  DictionaryModelsTests.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class DictionaryModelsTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        let schema = Schema([
            WordReplacement.self,
            VocabularyWord.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }
    
    // MARK: - WordReplacement Tests
    
    func testWordReplacementInitialization() throws {
        let replacement = WordReplacement(
            originals: ["teh", "teh"],
            replacement: "the"
        )
        
        XCTAssertNotNil(replacement.id)
        XCTAssertEqual(replacement.originals, ["teh", "teh"])
        XCTAssertEqual(replacement.replacement, "the")
        XCTAssertNotNil(replacement.createdAt)
        XCTAssertEqual(replacement.sortOrder, 0)
    }
    
    func testWordReplacementWithCustomValues() throws {
        let customDate = Date().addingTimeInterval(-3600)
        let customID = UUID()
        let replacement = WordReplacement(
            id: customID,
            originals: ["adn", "becuase"],
            replacement: "and",
            createdAt: customDate,
            sortOrder: 5
        )
        
        XCTAssertEqual(replacement.id, customID)
        XCTAssertEqual(replacement.originals, ["adn", "becuase"])
        XCTAssertEqual(replacement.replacement, "and")
        XCTAssertEqual(replacement.createdAt, customDate)
        XCTAssertEqual(replacement.sortOrder, 5)
    }
    
    func testWordReplacementPersists() throws {
        let replacement = WordReplacement(
            originals: ["teh"],
            replacement: "the",
            sortOrder: 1
        )
        modelContext.insert(replacement)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<WordReplacement>()
        let savedReplacements = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(savedReplacements.count, 1)
        XCTAssertEqual(savedReplacements.first?.originals, ["teh"])
        XCTAssertEqual(savedReplacements.first?.replacement, "the")
        XCTAssertEqual(savedReplacements.first?.sortOrder, 1)
    }
    
    func testWordReplacementUniqueIDs() throws {
        let replacement1 = WordReplacement(originals: ["teh"], replacement: "the")
        let replacement2 = WordReplacement(originals: ["adn"], replacement: "and")
        
        modelContext.insert(replacement1)
        modelContext.insert(replacement2)
        try modelContext.save()
        
        XCTAssertNotEqual(replacement1.id, replacement2.id)
    }
    
    func testWordReplacementEmptyOriginals() throws {
        let replacement = WordReplacement(
            originals: [],
            replacement: "test"
        )
        
        XCTAssertTrue(replacement.originals.isEmpty)
        XCTAssertEqual(replacement.replacement, "test")
    }
    
    func testWordReplacementMultipleOriginals() throws {
        let originals = ["teh", "teh", "teh"]
        let replacement = WordReplacement(
            originals: originals,
            replacement: "the"
        )
        
        XCTAssertEqual(replacement.originals.count, 3)
        XCTAssertEqual(replacement.originals, ["teh", "teh", "teh"])
    }
    
    // MARK: - VocabularyWord Tests
    
    func testVocabularyWordInitialization() throws {
        let word = VocabularyWord(word: "perspicacious")
        
        XCTAssertNotNil(word.id)
        XCTAssertEqual(word.word, "perspicacious")
        XCTAssertNotNil(word.createdAt)
    }
    
    func testVocabularyWordWithCustomValues() throws {
        let customDate = Date().addingTimeInterval(-7200)
        let customID = UUID()
        let word = VocabularyWord(
            id: customID,
            word: "sesquipedalian",
            createdAt: customDate
        )
        
        XCTAssertEqual(word.id, customID)
        XCTAssertEqual(word.word, "sesquipedalian")
        XCTAssertEqual(word.createdAt, customDate)
    }
    
    func testVocabularyWordPersists() throws {
        let word = VocabularyWord(word: "ephemeral")
        modelContext.insert(word)
        try modelContext.save()
        
        let descriptor = FetchDescriptor<VocabularyWord>()
        let savedWords = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(savedWords.count, 1)
        XCTAssertEqual(savedWords.first?.word, "ephemeral")
    }
    
    func testVocabularyWordUniqueIDs() throws {
        let word1 = VocabularyWord(word: "hello")
        let word2 = VocabularyWord(word: "world")
        
        modelContext.insert(word1)
        modelContext.insert(word2)
        try modelContext.save()
        
        XCTAssertNotEqual(word1.id, word2.id)
    }
    
    func testVocabularyWordEmptyWord() throws {
        let word = VocabularyWord(word: "")
        
        XCTAssertEqual(word.word, "")
        XCTAssertNotNil(word.id)
        XCTAssertNotNil(word.createdAt)
    }
    
    // MARK: - Schema Tests
    
    func testSchemaContainsBothModels() throws {
        let schema = Schema([
            WordReplacement.self,
            VocabularyWord.self
        ])
        
        let descriptor = FetchDescriptor<WordReplacement>()
        let replacementDescriptor = FetchDescriptor<VocabularyWord>()
        
        XCTAssertNoThrow(try modelContext.fetch(descriptor))
        XCTAssertNoThrow(try modelContext.fetch(replacementDescriptor))
    }
}
