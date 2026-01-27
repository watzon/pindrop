//
//  DictionaryStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class DictionaryStoreTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var dictionaryStore: DictionaryStore!
    
    override func setUp() async throws {
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        dictionaryStore = DictionaryStore(modelContext: modelContext)
    }
    
    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        dictionaryStore = nil
    }
    
    // MARK: - WordReplacement CRUD Tests
    
    func testAddWordReplacement() throws {
        let replacement = WordReplacement(
            originals: ["dr", "Dr"],
            replacement: "Doctor",
            sortOrder: 0
        )
        
        try dictionaryStore.add(replacement)
        
        let replacements = try dictionaryStore.fetchAllReplacements()
        XCTAssertEqual(replacements.count, 1)
        XCTAssertEqual(replacements.first?.originals, ["dr", "Dr"])
        XCTAssertEqual(replacements.first?.replacement, "Doctor")
    }
    
    func testFetchAllReplacements() throws {
        let r1 = WordReplacement(originals: ["a"], replacement: "A", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "B", sortOrder: 1)
        let r3 = WordReplacement(originals: ["c"], replacement: "C", sortOrder: 2)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        try dictionaryStore.add(r3)
        
        let replacements = try dictionaryStore.fetchAllReplacements()
        XCTAssertEqual(replacements.count, 3)
        XCTAssertEqual(replacements[0].sortOrder, 0)
        XCTAssertEqual(replacements[1].sortOrder, 1)
        XCTAssertEqual(replacements[2].sortOrder, 2)
    }
    
    func testDeleteWordReplacement() throws {
        let r1 = WordReplacement(originals: ["keep"], replacement: "Keep", sortOrder: 0)
        let r2 = WordReplacement(originals: ["delete"], replacement: "Delete", sortOrder: 1)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        
        var replacements = try dictionaryStore.fetchAllReplacements()
        XCTAssertEqual(replacements.count, 2)
        
        let toDelete = replacements.first { $0.originals.contains("delete") }!
        try dictionaryStore.delete(toDelete)
        
        replacements = try dictionaryStore.fetchAllReplacements()
        XCTAssertEqual(replacements.count, 1)
        XCTAssertEqual(replacements.first?.originals, ["keep"])
    }
    
    func testReorderReplacements() throws {
        let r1 = WordReplacement(originals: ["a"], replacement: "A", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "B", sortOrder: 1)
        let r3 = WordReplacement(originals: ["c"], replacement: "C", sortOrder: 2)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        try dictionaryStore.add(r3)
        
        var replacements = try dictionaryStore.fetchAllReplacements()
        try dictionaryStore.reorder(replacements, from: IndexSet(integer: 0), to: 3)
        
        replacements = try dictionaryStore.fetchAllReplacements()
        XCTAssertEqual(replacements[0].originals, ["b"])
        XCTAssertEqual(replacements[1].originals, ["c"])
        XCTAssertEqual(replacements[2].originals, ["a"])
    }
    
    // MARK: - VocabularyWord CRUD Tests
    
    func testAddVocabularyWord() throws {
        let word = VocabularyWord(word: "supercalifragilisticexpialidocious")
        
        try dictionaryStore.add(word)
        
        let words = try dictionaryStore.fetchAllVocabularyWords()
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.word, "supercalifragilisticexpialidocious")
    }
    
    func testFetchAllVocabularyWords() throws {
        let w1 = VocabularyWord(word: "apple")
        let w2 = VocabularyWord(word: "banana")
        let w3 = VocabularyWord(word: "cherry")
        
        try dictionaryStore.add(w1)
        try dictionaryStore.add(w2)
        try dictionaryStore.add(w3)
        
        let words = try dictionaryStore.fetchAllVocabularyWords()
        XCTAssertEqual(words.count, 3)
    }
    
    func testDeleteVocabularyWord() throws {
        let w1 = VocabularyWord(word: "keep")
        let w2 = VocabularyWord(word: "delete")
        
        try dictionaryStore.add(w1)
        try dictionaryStore.add(w2)
        
        var words = try dictionaryStore.fetchAllVocabularyWords()
        XCTAssertEqual(words.count, 2)
        
        let toDelete = words.first { $0.word == "delete" }!
        try dictionaryStore.delete(toDelete)
        
        words = try dictionaryStore.fetchAllVocabularyWords()
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.word, "keep")
    }
    
    // MARK: - applyReplacements Tests
    
    func testWordBoundaryMatching() throws {
        let r1 = WordReplacement(originals: ["dr"], replacement: "Doctor", sortOrder: 0)
        let r2 = WordReplacement(originals: ["is"], replacement: "was", sortOrder: 1)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        
        // "dr" should match "dr smith" but not "address"
        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "dr smith")
        XCTAssertEqual(result1, "Doctor smith")
        XCTAssertEqual(applied1.count, 1)
        XCTAssertEqual(applied1[0].original, "dr")
        XCTAssertEqual(applied1[0].replacement, "Doctor")
        
        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "address")
        XCTAssertEqual(result2, "address")
        XCTAssertEqual(applied2.count, 0)
        
        // "is" should match "this is a test" but not "this" or "test"
        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "this is a test")
        XCTAssertEqual(result3, "this was a test")
        XCTAssertEqual(applied3.count, 1)
        XCTAssertEqual(applied3[0].original, "is")
        XCTAssertEqual(applied3[0].replacement, "was")
    }
    
    func testCaseInsensitiveMatching() throws {
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)
        
        try dictionaryStore.add(r1)
        
        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "HELLO world")
        XCTAssertEqual(result1, "hi world")
        XCTAssertEqual(applied1.count, 1)
        
        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "Hello World")
        XCTAssertEqual(result2, "hi World")
        XCTAssertEqual(applied2.count, 1)
        
        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "hello there")
        XCTAssertEqual(result3, "hi there")
        XCTAssertEqual(applied3.count, 1)
    }
    
    func testLongerMatchWins() throws {
        let r1 = WordReplacement(originals: ["new york"], replacement: "NYC", sortOrder: 0)
        let r2 = WordReplacement(originals: ["york"], replacement: "York City", sortOrder: 1)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        
        // "new york" should match first, preventing "york" from matching
        let (result, applied) = try dictionaryStore.applyReplacements(to: "new york city")
        XCTAssertEqual(result, "NYC city")
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].original, "new york")
        XCTAssertEqual(applied[0].replacement, "NYC")
    }
    
    func testSinglePassReplacement() throws {
        let r1 = WordReplacement(originals: ["a"], replacement: "b", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "c", sortOrder: 1)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        
        // "a" should become "b", NOT "c" (single pass)
        let (result, applied) = try dictionaryStore.applyReplacements(to: "a")
        XCTAssertEqual(result, "b")
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied[0].original, "a")
        XCTAssertEqual(applied[0].replacement, "b")
    }
    
    func testMultipleOriginalsPerReplacement() throws {
        let r1 = WordReplacement(
            originals: ["dr", "Dr", "DR"],
            replacement: "Doctor",
            sortOrder: 0
        )
        
        try dictionaryStore.add(r1)
        
        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "dr smith")
        XCTAssertEqual(result1, "Doctor smith")
        XCTAssertEqual(applied1.count, 1)
        
        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "Dr Jones")
        XCTAssertEqual(result2, "Doctor Jones")
        XCTAssertEqual(applied2.count, 1)
        
        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "DR Brown")
        XCTAssertEqual(result3, "Doctor Brown")
        XCTAssertEqual(applied3.count, 1)
    }
    
    func testNoReplacements() throws {
        let (result, applied) = try dictionaryStore.applyReplacements(to: "hello world")
        XCTAssertEqual(result, "hello world")
        XCTAssertEqual(applied.count, 0)
    }
    
    func testEmptyInput() throws {
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)
        try dictionaryStore.add(r1)
        
        let (result, applied) = try dictionaryStore.applyReplacements(to: "")
        XCTAssertEqual(result, "")
        XCTAssertEqual(applied.count, 0)
    }
    
    func testMultipleReplacementsInSameText() throws {
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)
        let r2 = WordReplacement(originals: ["world"], replacement: "universe", sortOrder: 1)
        
        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        
        let (result, applied) = try dictionaryStore.applyReplacements(to: "hello world")
        XCTAssertEqual(result, "hi universe")
        XCTAssertEqual(applied.count, 2)
        XCTAssertTrue(applied.contains { $0.original == "hello" && $0.replacement == "hi" })
        XCTAssertTrue(applied.contains { $0.original == "world" && $0.replacement == "universe" })
    }
    
    func testSpecialCharactersInReplacement() throws {
        let r1 = WordReplacement(originals: ["test"], replacement: "test-123", sortOrder: 0)
        
        try dictionaryStore.add(r1)
        
        let (result, applied) = try dictionaryStore.applyReplacements(to: "this is a test")
        XCTAssertEqual(result, "this is a test-123")
        XCTAssertEqual(applied.count, 1)
    }
}
