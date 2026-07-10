//
//  VocabularyBiasPromptTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct VocabularyBiasPromptTests {
    @Test func selectWordsReturnsEmptyForEmptyInput() {
        #expect(VocabularyBiasPrompt.selectWords(from: []).isEmpty)
        #expect(VocabularyBiasPrompt.assemblePrompt(words: []) == nil)
        #expect(VocabularyBiasPrompt.prompt(from: []) == nil)
    }

    @Test func selectWordsDropsBlankEntries() {
        let entries = [
            VocabularyBiasPrompt.Entry(word: "  ", usageCount: 5, createdAt: Date()),
            VocabularyBiasPrompt.Entry(word: "kept", usageCount: 1, createdAt: Date()),
        ]
        #expect(VocabularyBiasPrompt.selectWords(from: entries) == ["kept"])
    }

    @Test func selectWordsPrefersHigherUsageThenMoreRecent() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let entries = [
            VocabularyBiasPrompt.Entry(word: "a", usageCount: 1, createdAt: newer),
            VocabularyBiasPrompt.Entry(word: "b", usageCount: 3, createdAt: older),
            VocabularyBiasPrompt.Entry(word: "c", usageCount: 3, createdAt: newer),
            VocabularyBiasPrompt.Entry(word: "d", usageCount: 2, createdAt: newer),
        ]
        #expect(VocabularyBiasPrompt.selectWords(from: entries) == ["c", "b", "d", "a"])
    }

    @Test func selectWordsRespectsLimitAndDedupesCaseInsensitively() {
        let now = Date()
        var entries: [VocabularyBiasPrompt.Entry] = []
        for i in 0..<50 {
            entries.append(
                VocabularyBiasPrompt.Entry(word: "word\(i)", usageCount: i, createdAt: now)
            )
        }
        entries.append(
            VocabularyBiasPrompt.Entry(word: "WORD49", usageCount: 100, createdAt: now)
        )

        let selected = VocabularyBiasPrompt.selectWords(from: entries, limit: 5)
        #expect(selected.count == 5)
        // WORD49 wins over word49 due to higher usage; then word48..word45
        #expect(selected[0] == "WORD49")
        #expect(selected[1] == "word48")
        #expect(!selected.contains("word49"))
    }

    @Test func assemblePromptJoinsWithComma() {
        #expect(VocabularyBiasPrompt.assemblePrompt(words: ["Alpha", "Beta"]) == "Alpha, Beta")
    }

    @Test func maxWordCountIsForty() {
        #expect(VocabularyBiasPrompt.maxWordCount == 40)
    }

    @Test func commandPaletteResolvesNamedTokens() {
        #expect(ReplacementCommandPalette.resolve("newParagraph") == "\n\n")
        #expect(ReplacementCommandPalette.resolve("new paragraph") == "\n\n")
        #expect(ReplacementCommandPalette.resolve("newLine") == "\n")
        #expect(ReplacementCommandPalette.resolve("new line") == "\n")
        #expect(ReplacementCommandPalette.resolve("tab") == "\t")
        #expect(ReplacementCommandPalette.resolve("TAB") == "\t")
    }

    @Test func commandPaletteKeepsLiteralSequencesAndUnknowns() {
        #expect(ReplacementCommandPalette.resolve("\n\n") == "\n\n")
        #expect(ReplacementCommandPalette.resolve("\n") == "\n")
        #expect(ReplacementCommandPalette.resolve("\t") == "\t")
        #expect(ReplacementCommandPalette.resolve("custom") == "custom")
    }
}
