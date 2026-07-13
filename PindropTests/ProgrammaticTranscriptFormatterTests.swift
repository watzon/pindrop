//
//  ProgrammaticTranscriptFormatterTests.swift
//  Pindrop
//
//  Created on 2026-07-13.
//
//  Spec for the local programmatic paragraph-formatting pass and its settings seam.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct ProgrammaticTranscriptFormatterTests {

    private let formatter = ProgrammaticTranscriptFormatter()

    // MARK: - Disabled / identity

    @Test func formatIfEnabledDisabledIsByteForByteIdentity() {
        let input = "Hello world. This is a long enough sample sentence for testing identity."
        #expect(ProgrammaticTranscriptFormatter.formatIfEnabled(input, enabled: false) == input)
    }

    @Test func formatIfEnabledDisabledPreservesExactWhitespace() {
        let input = "  keep me exactly.  "
        #expect(ProgrammaticTranscriptFormatter.formatIfEnabled(input, enabled: false) == input)
    }

    @Test func formatIfEnabledTrueDelegatesToFormat() {
        let input = """
        This is the first sentence of a longer dictation sample. This is the second sentence that continues the thought. This is the third sentence with more content. This is the fourth sentence wrapping things up cleanly.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(
            ProgrammaticTranscriptFormatter.formatIfEnabled(input, enabled: true)
                == formatter.format(input)
        )
        #expect(formatter.format(input).contains("\n\n"))
    }

    // MARK: - Short utterances stay single-line

    @Test func leavesShortUtterancesUnchanged() {
        let input = "Hello there. How are you?"
        #expect(formatter.format(input) == input)
    }

    @Test func leavesSingleSentenceUnchangedEvenWhenLong() {
        let input = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces) + "."
        #expect(formatter.format(input) == input)
    }

    @Test func leavesLongTwoSentenceTextUnchanged() {
        // Two sentences can never create a blank-line break when grouping size is 2;
        // minimumSentenceCount is sentencesPerParagraph + 1.
        let input = """
        This is a deliberately long first sentence with plenty of words to clear the character and word floors for the formatter. This second sentence is also long enough that only the sentence-count gate should keep the text single-line.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(input.count >= ProgrammaticTranscriptFormatter.minimumCharacterCount)
        #expect(
            input.split(whereSeparator: \.isWhitespace).count
                >= ProgrammaticTranscriptFormatter.minimumWordCount
        )
        #expect(ProgrammaticTranscriptFormatter.splitSentences(input).count == 2)
        #expect(formatter.format(input) == input)
        #expect(!formatter.format(input).contains("\n\n"))
    }

    // MARK: - Sentence grouping into paragraphs

    @Test func groupsSentencesWithBlankLineParagraphBreaks() {
        let input = """
        This is the first sentence of a longer dictation sample. This is the second sentence that continues the thought. This is the third sentence with more content. This is the fourth sentence wrapping things up cleanly.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let output = formatter.format(input)
        #expect(output.contains("\n\n"))
        #expect(!output.contains("\n\n\n"))

        let paragraphs = output.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].contains("first sentence"))
        #expect(paragraphs[0].contains("second sentence"))
        #expect(paragraphs[1].contains("third sentence"))
        #expect(paragraphs[1].contains("fourth sentence"))
    }

    @Test func keepsOddTrailingSentenceInFinalParagraph() {
        let input = """
        Alpha sentence one is long enough for the test case. Beta sentence two continues the idea further. Gamma sentence three finishes the remaining idea without needing more.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let output = formatter.format(input)
        let paragraphs = output.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 2)
        #expect(paragraphs[1].contains("Gamma sentence three"))
    }

    // MARK: - Existing newlines preserved

    @Test func preservesExistingBlankLineFormatting() {
        let input = "Already formatted paragraph one.\n\nAlready formatted paragraph two with more words here."
        #expect(formatter.format(input) == input)
    }

    @Test func preservesSingleNewlinesWithoutRewriting() {
        let input = "Line one with enough words to look substantial.\nLine two with enough words as well for safety."
        #expect(formatter.format(input) == input)
    }

    // MARK: - Sentence boundary / closers

    @Test func consumesStraightQuotesIntoCompletedSentence() {
        let input = #"He said "Hello." Then we left the room quietly after lunch."#
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0] == #"He said "Hello.""#)
        #expect(sentences[1] == "Then we left the room quietly after lunch.")
    }

    @Test func consumesCurlyQuotesIntoCompletedSentence() {
        let input = "He said “Hello.” Then we left the room quietly after lunch."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0] == "He said “Hello.”")
        #expect(sentences[1] == "Then we left the room quietly after lunch.")
    }

    @Test func consumesClosingParenthesisIntoCompletedSentence() {
        // Closer trails the terminator: `!)` still belongs to the same sentence.
        let input = "Was it ready (yes!) Then everyone went home for the evening."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0] == "Was it ready (yes!)")
        #expect(sentences[1] == "Then everyone went home for the evening.")
    }
    // MARK: - Abbreviations / decimals

    @Test func doesNotSplitOnCommonAbbreviations() {
        let input = """
        I met Dr. Smith this morning about the project timeline and budget. We also reviewed Mr. Jones' notes from last week carefully. Then we confirmed the next steps for delivery.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 3)
        #expect(sentences[0].contains("Dr. Smith"))
        #expect(sentences[1].contains("Mr. Jones"))
    }

    @Test func splitsOnUsAsSentenceEndingWord() {
        let input = "Please contact us. Then follow the next steps carefully."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0] == "Please contact us.")
        #expect(sentences[1] == "Then follow the next steps carefully.")
    }

    @Test func splitsOnNoAsSentenceEndingWord() {
        let input = "No. Continue with the remaining items on the list."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0] == "No.")
        #expect(sentences[1] == "Continue with the remaining items on the list.")
    }

    @Test func doesNotSplitOnUSInitialism() {
        let input = "She moved to the U.S. after finishing school last spring."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 1)
        #expect(sentences[0].contains("U.S."))
    }

    @Test func doesNotSplitOnNumberAbbreviationBeforeDigit() {
        // `No. 5` must not become a sentence break; boundary requires a following letter.
        let input = "See item No. 5 in the appendix for details."
        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 1)
        #expect(sentences[0].contains("No. 5"))
    }

    @Test func doesNotSplitOnDecimalNumbers() {
        let input = """
        The reading was 3.14 units during the morning check and remained stable. Later it climbed to 12.5 units after the adjustment period finished. We logged both values carefully.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 3)
        #expect(sentences[0].contains("3.14"))
        #expect(sentences[1].contains("12.5"))
    }

    @Test func doesNotSplitOnInitials() {
        let input = """
        Author J. K. Rowling signed copies at the store for nearly two hours today. Fans waited outside until the session officially closed.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0].contains("J. K. Rowling"))
    }

    @Test func doesNotSplitOnEllipsis() {
        let input = """
        I was thinking about the plan... and then I changed my mind after lunch. We decided to revisit the idea tomorrow morning instead.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = ProgrammaticTranscriptFormatter.splitSentences(input)
        #expect(sentences.count == 2)
        #expect(sentences[0].contains("..."))
    }

    // MARK: - Settings default (production seam)

    @Test @MainActor func programmaticFormattingDefaultsToDisabled() {
        let store = SettingsStore()
        store.resetAllSettings()
        defer { store.resetAllSettings() }

        #expect(store.programmaticFormattingEnabled == false)
        #expect(SettingsStore.Defaults.programmaticFormattingEnabled == false)

        store.programmaticFormattingEnabled = true
        #expect(store.programmaticFormattingEnabled)

        store.resetAllSettings()
        #expect(store.programmaticFormattingEnabled == false)
    }

    @Test @MainActor func settingsGateMatchesFormatIfEnabledContract() {
        // Production call sites pass settingsStore.programmaticFormattingEnabled into
        // formatIfEnabled. Verify that gate preserves disabled identity and formats when on.
        let store = SettingsStore()
        store.resetAllSettings()
        defer { store.resetAllSettings() }

        let raw = """
        This is the first sentence of a longer dictation sample. This is the second sentence that continues the thought. This is the third sentence with more content. This is the fourth sentence wrapping things up cleanly.
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(
            ProgrammaticTranscriptFormatter.formatIfEnabled(
                raw,
                enabled: store.programmaticFormattingEnabled
            ) == raw
        )

        store.programmaticFormattingEnabled = true
        let gated = ProgrammaticTranscriptFormatter.formatIfEnabled(
            raw,
            enabled: store.programmaticFormattingEnabled
        )
        #expect(gated == formatter.format(raw))
        #expect(gated.contains("\n\n"))
    }
}
