//
//  DictionaryModelsTests.swift
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
struct DictionaryModelsTests {
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([WordReplacement.self, VocabularyWord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(modelContainer)
    }

    @Test func wordReplacementInitialization() {
        let replacement = WordReplacement(originals: ["teh", "teh"], replacement: "the")

        #expect(replacement.originals == ["teh", "teh"])
        #expect(replacement.replacement == "the")
        #expect(replacement.sortOrder == 0)
    }

    @Test func wordReplacementWithCustomValues() {
        let customDate = Date().addingTimeInterval(-3600)
        let customID = UUID()
        let replacement = WordReplacement(
            id: customID,
            originals: ["adn", "becuase"],
            replacement: "and",
            createdAt: customDate,
            sortOrder: 5
        )

        #expect(replacement.id == customID)
        #expect(replacement.originals == ["adn", "becuase"])
        #expect(replacement.replacement == "and")
        #expect(replacement.createdAt == customDate)
        #expect(replacement.sortOrder == 5)
    }

    @Test func wordReplacementPersists() throws {
        let modelContext = try makeModelContext()
        let replacement = WordReplacement(originals: ["teh"], replacement: "the", sortOrder: 1)
        modelContext.insert(replacement)
        try modelContext.save()

        let savedReplacements = try modelContext.fetch(FetchDescriptor<WordReplacement>())
        #expect(savedReplacements.count == 1)
        #expect(savedReplacements.first?.originals == ["teh"])
        #expect(savedReplacements.first?.replacement == "the")
        #expect(savedReplacements.first?.sortOrder == 1)
    }

    @Test func wordReplacementUniqueIDs() throws {
        let modelContext = try makeModelContext()
        let replacement1 = WordReplacement(originals: ["teh"], replacement: "the")
        let replacement2 = WordReplacement(originals: ["adn"], replacement: "and")

        modelContext.insert(replacement1)
        modelContext.insert(replacement2)
        try modelContext.save()

        #expect(replacement1.id != replacement2.id)
    }

    @Test func wordReplacementEmptyOriginals() {
        let replacement = WordReplacement(originals: [], replacement: "test")
        #expect(replacement.originals.isEmpty)
        #expect(replacement.replacement == "test")
    }

    @Test func wordReplacementMultipleOriginals() {
        let originals = ["teh", "teh", "teh"]
        let replacement = WordReplacement(originals: originals, replacement: "the")
        #expect(replacement.originals.count == 3)
        #expect(replacement.originals == originals)
    }

    @Test func vocabularyWordInitialization() {
        let word = VocabularyWord(word: "perspicacious")
        #expect(word.word == "perspicacious")
    }

    @Test func vocabularyWordWithCustomValues() {
        let customDate = Date().addingTimeInterval(-7200)
        let customID = UUID()
        let word = VocabularyWord(id: customID, word: "sesquipedalian", createdAt: customDate)

        #expect(word.id == customID)
        #expect(word.word == "sesquipedalian")
        #expect(word.createdAt == customDate)
    }

    @Test func vocabularyWordPersists() throws {
        let modelContext = try makeModelContext()
        let word = VocabularyWord(word: "ephemeral")
        modelContext.insert(word)
        try modelContext.save()

        let savedWords = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
        #expect(savedWords.count == 1)
        #expect(savedWords.first?.word == "ephemeral")
    }

    @Test func vocabularyWordUniqueIDs() throws {
        let modelContext = try makeModelContext()
        let word1 = VocabularyWord(word: "hello")
        let word2 = VocabularyWord(word: "world")

        modelContext.insert(word1)
        modelContext.insert(word2)
        try modelContext.save()

        #expect(word1.id != word2.id)
    }

    @Test func vocabularyWordEmptyWord() {
        let word = VocabularyWord(word: "")
        #expect(word.word == "")
    }

    @Test func schemaContainsBothModels() throws {
        let modelContext = try makeModelContext()
        #expect(throws: Never.self) {
            _ = try modelContext.fetch(FetchDescriptor<WordReplacement>())
        }
        #expect(throws: Never.self) {
            _ = try modelContext.fetch(FetchDescriptor<VocabularyWord>())
        }
    }
}
