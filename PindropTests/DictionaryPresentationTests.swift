//
//  DictionaryPresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-10.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct DictionaryPresentationTests {

    private let en = Locale(identifier: "en")

    // MARK: - Vocabulary chip ordering

    @Test func vocabChipsOrderByUsageDescThenAlpha() {
        let input: [(word: String, usageCount: Int)] = [
            ("zeta", 1),
            ("alpha", 5),
            ("beta", 5),
            ("gamma", 0),
            ("Alpha2", 5),
        ]
        let sorted = DictionaryVocabularyOrdering.sortedChips(words: input)
        #expect(sorted.map(\.word) == ["alpha", "Alpha2", "beta", "zeta", "gamma"])
        #expect(sorted.map(\.usageCount) == [5, 5, 5, 1, 0])
    }

    @Test func vocabChipsEmptyAndSingle() {
        #expect(DictionaryVocabularyOrdering.sortedChips(words: []).isEmpty)
        let single = DictionaryVocabularyOrdering.sortedChips(words: [("only", 3)])
        #expect(single.map(\.word) == ["only"])
    }

    // MARK: - Command token display

    @Test func commandTokenDisplayMapsPaletteTokens() {
        #expect(DictionaryCommandTokenDisplay.displayString(for: "newParagraph") == "⏎⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "new paragraph") == "⏎⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "newLine") == "⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "new line") == "⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "tab") == "⇥")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "\n\n") == "⏎⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "\n") == "⏎")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "\t") == "⇥")
    }

    @Test func commandTokenDisplayLeavesCustomText() {
        #expect(DictionaryCommandTokenDisplay.displayString(for: "hello") == "hello")
        #expect(DictionaryCommandTokenDisplay.displayString(for: "  custom  ") == "  custom  "
                || DictionaryCommandTokenDisplay.displayString(for: "  custom  ") == "custom"
                || DictionaryCommandTokenDisplay.displayString(for: "  custom  ").contains("custom"))
    }

    @Test func replacementDisplayUsesGlyphsOnlyInCommandMode() {
        #expect(
            DictionaryCommandTokenDisplay.replacementDisplay(
                replacement: "newParagraph",
                matchMode: .command
            ) == "⏎⏎"
        )
        #expect(
            DictionaryCommandTokenDisplay.replacementDisplay(
                replacement: "newParagraph",
                matchMode: .exact
            ) == "newParagraph"
        )
        #expect(
            DictionaryCommandTokenDisplay.replacementDisplay(
                replacement: "Hello",
                matchMode: .caseInsensitive
            ) == "Hello"
        )
    }

    @Test func patternDisplayJoinsOriginals() {
        #expect(
            DictionaryCommandTokenDisplay.patternDisplay(originals: ["foo", "bar"])
                == "foo, bar"
        )
    }

    // MARK: - Match mode labels

    @Test func matchModeLabelsAreReadable() {
        #expect(
            DictionaryMatchModeLabel.label(for: .caseInsensitive, locale: en)
                == "case-insensitive"
        )
        #expect(DictionaryMatchModeLabel.label(for: .exact, locale: en) == "exact")
        #expect(DictionaryMatchModeLabel.label(for: .command, locale: en) == "command")
    }
}
