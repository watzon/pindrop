//
//  ReplacementMatchModeTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct ReplacementMatchModeTests {
    @Test func nilRawValueFallsBackToCaseInsensitive() {
        let sut = WordReplacement(originals: ["teh"], replacement: "the")
        #expect(sut.matchModeRawValue == nil)
        #expect(sut.matchMode == .caseInsensitive)
    }

    @Test func unknownRawValueFallsBackToCaseInsensitive() {
        let sut = WordReplacement(
            originals: ["teh"],
            replacement: "the",
            matchModeRawValue: "not-a-real-mode"
        )
        #expect(sut.matchMode == .caseInsensitive)
    }

    @Test func knownRawValuesResolve() {
        let exact = WordReplacement(
            originals: ["Teh"],
            replacement: "the",
            matchModeRawValue: ReplacementMatchMode.exact.rawValue
        )
        #expect(exact.matchMode == .exact)

        let command = WordReplacement(
            originals: ["new paragraph"],
            replacement: "\n\n",
            matchModeRawValue: ReplacementMatchMode.command.rawValue
        )
        #expect(command.matchMode == .command)

        let caseInsensitive = WordReplacement(
            originals: ["teh"],
            replacement: "the",
            matchModeRawValue: ReplacementMatchMode.caseInsensitive.rawValue
        )
        #expect(caseInsensitive.matchMode == .caseInsensitive)
    }

    @Test func usageCountDefaultsToZero() {
        let replacement = WordReplacement(originals: ["a"], replacement: "A")
        #expect(replacement.usageCount == 0)

        let vocabulary = VocabularyWord(word: "Pindrop")
        #expect(vocabulary.usageCount == 0)
    }
}
