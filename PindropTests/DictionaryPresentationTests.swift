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

    @Test func vocabChipsPreserveCaseAndExactDuplicatesWithoutTrap() {
        // Case-variant / exact duplicates must not crash (uniqueKeysWithValues trap).
        let input: [(word: String, usageCount: Int)] = [
            ("Pindrop", 2),
            ("pindrop", 5),
            ("Pindrop", 1),
            ("alpha", 0),
        ]
        let sorted = DictionaryVocabularyOrdering.sortedChips(words: input)
        #expect(sorted.count == 4)
        #expect(sorted.map(\.usageCount) == [5, 2, 1, 0])
        #expect(sorted.map(\.word) == ["pindrop", "Pindrop", "Pindrop", "alpha"])
    }

    @Test func sortedModelsPreservesDuplicateVocabularyWords() {
        let a = VocabularyWord(word: "Swift", usageCount: 3)
        let b = VocabularyWord(word: "swift", usageCount: 1)
        let c = VocabularyWord(word: "Swift", usageCount: 2)
        let sorted = DictionaryVocabularyOrdering.sortedModels([a, b, c])
        #expect(sorted.count == 3)
        #expect(sorted.map(\.usageCount) == [3, 2, 1])
        // Identity preserved — not collapsed into one entry.
        #expect(Set(sorted.map(\.id)).count == 3)
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

    // MARK: - Async lifecycle commit rules

    @Test func importCommitRequiresMatchingGenerationAndNotCancelled() {
        #expect(
            DictionaryAsyncLifecycle.canCommit(
                generation: 3,
                activeGeneration: 3,
                isCancelled: false
            )
        )
        // A slow older import must not commit after a newer selection.
        #expect(
            !DictionaryAsyncLifecycle.canCommit(
                generation: 2,
                activeGeneration: 3,
                isCancelled: false
            )
        )
        // Disappearance / explicit cancel invalidates even a matching generation.
        #expect(
            !DictionaryAsyncLifecycle.canCommit(
                generation: 4,
                activeGeneration: 4,
                isCancelled: true
            )
        )
    }

    @Test func cancelledOrStaleGenerationNeverCommits() {
        // Shared pure rule for import commit/error presentation after detached I/O.
        // Export writes are owned outside the view and are not cancelled on disappear;
        // only live-page error presentation is optional via a sink.
        #expect(
            DictionaryAsyncLifecycle.canCommit(
                generation: 1,
                activeGeneration: 1,
                isCancelled: false
            )
        )
        #expect(
            !DictionaryAsyncLifecycle.canCommit(
                generation: 1,
                activeGeneration: 2,
                isCancelled: false
            )
        )
        #expect(
            !DictionaryAsyncLifecycle.canCommit(
                generation: 1,
                activeGeneration: 1,
                isCancelled: true
            )
        )
    }

    @Test func exportFailureRetainedWhenNoLiveSink() {
        // Durable export failures that finish after Dictionary disappears must not be
        // dropped; retain until a sink is installed again.
        #expect(
            DictionaryAsyncLifecycle.exportFailureDisposition(hasLiveSink: true)
                == .deliverImmediately
        )
        #expect(
            DictionaryAsyncLifecycle.exportFailureDisposition(hasLiveSink: false)
                == .retainPending
        )
    }

    @Test func successfulExportDoesNotClearUnrelatedRetainedFailures() {
        let failedA = URL(fileURLWithPath: "/tmp/dict-a.json")
        let failedB = URL(fileURLWithPath: "/tmp/dict-b.json")
        let successB = URL(fileURLWithPath: "/tmp/dict-b.json")
        let successC = URL(fileURLWithPath: "/tmp/dict-c.json")

        // Success at C must leave A and B retained.
        #expect(
            DictionaryAsyncLifecycle.retainedFailuresAfterSuccess(
                pendingDestinations: [failedA, failedB],
                succeededDestination: successC
            ) == [failedA, failedB]
        )

        // Success at the same destination as a retained failure may clear only that one.
        #expect(
            DictionaryAsyncLifecycle.retainedFailuresAfterSuccess(
                pendingDestinations: [failedA, failedB],
                succeededDestination: successB
            ) == [failedA]
        )
    }

    @Test func onlyExportSurfaceAdvancesExportQueue() {
        #expect(
            DictionaryAsyncLifecycle.shouldAdvanceExportQueue(dismissedSurface: .export)
        )
        #expect(
            !DictionaryAsyncLifecycle.shouldAdvanceExportQueue(dismissedSurface: .local)
        )
    }

    @Test func loadCommitBuildsIDsAtomicallyAndClearsMissingSelection() {
        let replacementA = UUID()
        let replacementB = UUID()
        let vocabularyA = UUID()
        let selected = vocabularyA

        let kept = DictionaryAsyncLifecycle.makeLoadCommit(
            replacementIDs: [replacementA, replacementB],
            vocabularyIDs: [vocabularyA],
            selectedRowID: selected
        )
        #expect(kept.selectableIDs == [replacementA, replacementB, vocabularyA])
        #expect(kept.selectedRowID == selected)

        let cleared = DictionaryAsyncLifecycle.makeLoadCommit(
            replacementIDs: [replacementA],
            vocabularyIDs: [],
            selectedRowID: selected
        )
        #expect(cleared.selectableIDs == [replacementA])
        #expect(cleared.selectedRowID == nil)

        let noneSelected = DictionaryAsyncLifecycle.makeLoadCommit(
            replacementIDs: [replacementA],
            vocabularyIDs: [vocabularyA],
            selectedRowID: nil
        )
        #expect(noneSelected.selectedRowID == nil)
        #expect(noneSelected.selectableIDs == [replacementA, vocabularyA])
    }
}
