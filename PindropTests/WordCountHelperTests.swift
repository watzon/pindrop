//
//  WordCountHelperTests.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct WordCountHelperTests {
    @Test func emptyStringHasZeroWords() {
        #expect("".wordCount == 0)
        #expect("   ".wordCount == 0)
        #expect("\n\t  \n".wordCount == 0)
    }

    @Test func simpleWords() {
        #expect("hello".wordCount == 1)
        #expect("hello world".wordCount == 2)
        #expect("one two three".wordCount == 3)
    }

    @Test func multipleSpacesAreCollapsed() {
        #expect("hello    world".wordCount == 2)
        #expect("  padded  words  ".wordCount == 2)
    }

    @Test func newlinesSplitWords() {
        #expect("hello\nworld".wordCount == 2)
        #expect("one\ntwo\nthree".wordCount == 3)
        #expect("line one\n\nline two".wordCount == 4)
    }

    @Test func punctuationStaysAttachedToWords() {
        #expect("hello, world!".wordCount == 2)
        #expect("it's fine.".wordCount == 2)
        #expect("one—two".wordCount == 1)
    }

    @Test func effectiveWordCountUsesCacheWhenPresent() {
        let cached = TranscriptionRecord(
            text: "one two three four",
            duration: 1.0,
            modelUsed: "tiny",
            wordCount: 99
        )
        #expect(cached.effectiveWordCount == 99)

        let uncached = TranscriptionRecord(
            text: "one two three four",
            duration: 1.0,
            modelUsed: "tiny"
        )
        #expect(uncached.wordCount == nil)
        #expect(uncached.effectiveWordCount == 4)
    }
}
