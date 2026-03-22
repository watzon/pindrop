//
//  DictionaryStoreTests.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct DictionaryStoreTests {
    private func makeStore() throws -> DictionaryStore {
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(modelContainer)
        return DictionaryStore(modelContext: modelContext)
    }

    @Test func addWordReplacement() throws {
        let dictionaryStore = try makeStore()
        let replacement = WordReplacement(
            originals: ["dr", "Dr"],
            replacement: "Doctor",
            sortOrder: 0
        )

        try dictionaryStore.add(replacement)

        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 1)
        #expect(replacements.first?.originals == ["dr", "Dr"])
        #expect(replacements.first?.replacement == "Doctor")
    }

    @Test func fetchAllReplacements() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["a"], replacement: "A", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "B", sortOrder: 1)
        let r3 = WordReplacement(originals: ["c"], replacement: "C", sortOrder: 2)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        try dictionaryStore.add(r3)

        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 3)
        #expect(replacements[0].sortOrder == 0)
        #expect(replacements[1].sortOrder == 1)
        #expect(replacements[2].sortOrder == 2)
    }

    @Test func deleteWordReplacement() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["keep"], replacement: "Keep", sortOrder: 0)
        let r2 = WordReplacement(originals: ["delete"], replacement: "Delete", sortOrder: 1)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)

        var replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 2)

        let toDelete = try #require(replacements.first { $0.originals.contains("delete") })
        try dictionaryStore.delete(toDelete)

        replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 1)
        #expect(replacements.first?.originals == ["keep"])
    }

    @Test func reorderReplacements() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["a"], replacement: "A", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "B", sortOrder: 1)
        let r3 = WordReplacement(originals: ["c"], replacement: "C", sortOrder: 2)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)
        try dictionaryStore.add(r3)

        var replacements = try dictionaryStore.fetchAllReplacements()
        try dictionaryStore.reorder(replacements, from: IndexSet(integer: 0), to: 3)

        replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements[0].originals == ["b"])
        #expect(replacements[1].originals == ["c"])
        #expect(replacements[2].originals == ["a"])
    }

    @Test func addVocabularyWord() throws {
        let dictionaryStore = try makeStore()
        let word = VocabularyWord(word: "supercalifragilisticexpialidocious")

        try dictionaryStore.add(word)

        let words = try dictionaryStore.fetchAllVocabularyWords()
        #expect(words.count == 1)
        #expect(words.first?.word == "supercalifragilisticexpialidocious")
    }

    @Test func fetchAllVocabularyWords() throws {
        let dictionaryStore = try makeStore()
        let w1 = VocabularyWord(word: "apple")
        let w2 = VocabularyWord(word: "banana")
        let w3 = VocabularyWord(word: "cherry")

        try dictionaryStore.add(w1)
        try dictionaryStore.add(w2)
        try dictionaryStore.add(w3)

        let words = try dictionaryStore.fetchAllVocabularyWords()
        #expect(words.count == 3)
    }

    @Test func deleteVocabularyWord() throws {
        let dictionaryStore = try makeStore()
        let w1 = VocabularyWord(word: "keep")
        let w2 = VocabularyWord(word: "delete")

        try dictionaryStore.add(w1)
        try dictionaryStore.add(w2)

        var words = try dictionaryStore.fetchAllVocabularyWords()
        #expect(words.count == 2)

        let toDelete = try #require(words.first { $0.word == "delete" })
        try dictionaryStore.delete(toDelete)

        words = try dictionaryStore.fetchAllVocabularyWords()
        #expect(words.count == 1)
        #expect(words.first?.word == "keep")
    }

    @Test func upsertLearnedReplacementCreatesNewReplacement() throws {
        let dictionaryStore = try makeStore()
        let change = try dictionaryStore.upsertLearnedReplacement(original: "teh", replacement: "the")

        let requiredChange = try #require(change)
        #expect(requiredChange.learnedOriginal == "teh")
        #expect(requiredChange.replacement == "the")
        #expect(requiredChange.createdReplacement == true)

        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 1)
        #expect(replacements.first?.originals == ["teh"])
        #expect(replacements.first?.replacement == "the")
    }

    @Test func upsertLearnedReplacementMergesIntoExistingReplacement() throws {
        let dictionaryStore = try makeStore()
        try dictionaryStore.add(
            WordReplacement(
                originals: ["adress"],
                replacement: "address",
                sortOrder: 0
            )
        )

        let change = try dictionaryStore.upsertLearnedReplacement(original: "addres", replacement: "address")

        #expect(change?.createdReplacement == false)
        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 1)
        #expect(replacements.first?.originals == ["adress", "addres"])
    }

    @Test func undoLearnedReplacementRemovesOnlyLearnedOriginal() throws {
        let dictionaryStore = try makeStore()
        try dictionaryStore.add(
            WordReplacement(
                originals: ["adress"],
                replacement: "address",
                sortOrder: 0
            )
        )
        let change = try dictionaryStore.upsertLearnedReplacement(original: "addres", replacement: "address")

        try dictionaryStore.undoLearnedReplacement(try #require(change))

        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.count == 1)
        #expect(replacements.first?.originals == ["adress"])
    }

    @Test func undoLearnedReplacementDeletesEmptyReplacementRow() throws {
        let dictionaryStore = try makeStore()
        let change = try dictionaryStore.upsertLearnedReplacement(original: "teh", replacement: "the")

        try dictionaryStore.undoLearnedReplacement(try #require(change))

        let replacements = try dictionaryStore.fetchAllReplacements()
        #expect(replacements.isEmpty)
    }

    @Test func wordBoundaryMatching() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["dr"], replacement: "Doctor", sortOrder: 0)
        let r2 = WordReplacement(originals: ["is"], replacement: "was", sortOrder: 1)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)

        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "dr smith")
        #expect(result1 == "Doctor smith")
        #expect(applied1.count == 1)
        #expect(applied1[0].original == "dr")
        #expect(applied1[0].replacement == "Doctor")

        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "address")
        #expect(result2 == "address")
        #expect(applied2.count == 0)

        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "this is a test")
        #expect(result3 == "this was a test")
        #expect(applied3.count == 1)
        #expect(applied3[0].original == "is")
        #expect(applied3[0].replacement == "was")
    }

    @Test func caseInsensitiveMatching() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)

        try dictionaryStore.add(r1)

        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "HELLO world")
        #expect(result1 == "hi world")
        #expect(applied1.count == 1)

        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "Hello World")
        #expect(result2 == "hi World")
        #expect(applied2.count == 1)

        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "hello there")
        #expect(result3 == "hi there")
        #expect(applied3.count == 1)
    }

    @Test func longerMatchWins() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["new york"], replacement: "NYC", sortOrder: 0)
        let r2 = WordReplacement(originals: ["york"], replacement: "York City", sortOrder: 1)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)

        let (result, applied) = try dictionaryStore.applyReplacements(to: "new york city")
        #expect(result == "NYC city")
        #expect(applied.count == 1)
        #expect(applied[0].original == "new york")
        #expect(applied[0].replacement == "NYC")
    }

    @Test func singlePassReplacement() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["a"], replacement: "b", sortOrder: 0)
        let r2 = WordReplacement(originals: ["b"], replacement: "c", sortOrder: 1)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)

        let (result, applied) = try dictionaryStore.applyReplacements(to: "a")
        #expect(result == "b")
        #expect(applied.count == 1)
        #expect(applied[0].original == "a")
        #expect(applied[0].replacement == "b")
    }

    @Test func multipleOriginalsPerReplacement() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(
            originals: ["dr", "Dr", "DR"],
            replacement: "Doctor",
            sortOrder: 0
        )

        try dictionaryStore.add(r1)

        let (result1, applied1) = try dictionaryStore.applyReplacements(to: "dr smith")
        #expect(result1 == "Doctor smith")
        #expect(applied1.count == 1)

        let (result2, applied2) = try dictionaryStore.applyReplacements(to: "Dr Jones")
        #expect(result2 == "Doctor Jones")
        #expect(applied2.count == 1)

        let (result3, applied3) = try dictionaryStore.applyReplacements(to: "DR Brown")
        #expect(result3 == "Doctor Brown")
        #expect(applied3.count == 1)
    }

    @Test func noReplacements() throws {
        let dictionaryStore = try makeStore()
        let (result, applied) = try dictionaryStore.applyReplacements(to: "hello world")
        #expect(result == "hello world")
        #expect(applied.count == 0)
    }

    @Test func emptyInput() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)
        try dictionaryStore.add(r1)

        let (result, applied) = try dictionaryStore.applyReplacements(to: "")
        #expect(result == "")
        #expect(applied.count == 0)
    }

    @Test func multipleReplacementsInSameText() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["hello"], replacement: "hi", sortOrder: 0)
        let r2 = WordReplacement(originals: ["world"], replacement: "universe", sortOrder: 1)

        try dictionaryStore.add(r1)
        try dictionaryStore.add(r2)

        let (result, applied) = try dictionaryStore.applyReplacements(to: "hello world")
        #expect(result == "hi universe")
        #expect(applied.count == 2)
        #expect(applied.contains { $0.original == "hello" && $0.replacement == "hi" })
        #expect(applied.contains { $0.original == "world" && $0.replacement == "universe" })
    }

    @Test func specialCharactersInReplacement() throws {
        let dictionaryStore = try makeStore()
        let r1 = WordReplacement(originals: ["test"], replacement: "test-123", sortOrder: 0)

        try dictionaryStore.add(r1)

        let (result, applied) = try dictionaryStore.applyReplacements(to: "this is a test")
        #expect(result == "this is a test-123")
        #expect(applied.count == 1)
    }
}
