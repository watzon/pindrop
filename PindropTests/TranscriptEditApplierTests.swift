//
//  TranscriptEditApplierTests.swift
//  PindropTests
//
//  Created on 2026-04-17.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct TranscriptEditApplierTests {

   // MARK: - Basic path

   @Test func appliesMultipleEditsInOrder() {
      let input = "um this is a test of the system"
      let edits = [
         TranscriptEdit(find: "um this is", replacement: "This is"),
         TranscriptEdit(find: "system", replacement: "system."),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "This is a test of the system.")
      #expect(report.applied == 2)
      #expect(report.skippedFindNotPresent == 0)
      #expect(report.skippedFindAmbiguous == 0)
   }

   @Test func emptyEditListIsNoOp() {
      let input = "nothing changes here"
      let report = TranscriptEditApplier.apply(edits: [], to: input)
      #expect(report.resultingText == input)
      #expect(report.applied == 0)
      #expect(report.processed == 0)
   }

   // MARK: - Skip cases

   @Test func skipsFindThatDoesNotExist() {
      let input = "hello world"
      let edits = [
         TranscriptEdit(find: "goodbye", replacement: "farewell"),
         TranscriptEdit(find: "world", replacement: "World"),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "hello World")
      #expect(report.applied == 1)
      #expect(report.skippedFindNotPresent == 1)
   }

   @Test func skipsAmbiguousFindThatAppearsMultipleTimes() {
      let input = "the cat sat on the mat"
      let edits = [
         // "the" appears twice — model should have disambiguated, so skip rather than
         // guess which occurrence to replace.
         TranscriptEdit(find: "the", replacement: "a"),
         // Unambiguous — applies.
         TranscriptEdit(find: "cat sat", replacement: "Cat sat,"),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "the Cat sat, on the mat")
      #expect(report.applied == 1)
      #expect(report.skippedFindAmbiguous == 1)
   }

   @Test func skipsReplacementThatIntroducesUngroundedToken() {
      let input = "i think we should continue"
      // Model tries to complete with "today" which isn't in the input.
      let edits = [
         TranscriptEdit(find: "continue", replacement: "continue today")
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == input)
      #expect(report.applied == 0)
      #expect(report.skippedFindExtendsBeyondInput == 1)
   }

   @Test func allowsReplacementThatOnlyAddsPunctuation() {
      let input = "is this working"
      let edits = [
         TranscriptEdit(find: "is this working", replacement: "Is this working?")
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "Is this working?")
      #expect(report.applied == 1)
      #expect(report.skippedFindExtendsBeyondInput == 0)
   }

   @Test func skipsNoOpEdits() {
      let input = "already clean"
      let edits = [
         TranscriptEdit(find: "already", replacement: "already"),  // no-op
         TranscriptEdit(find: "clean", replacement: "clean!"),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "already clean!")
      #expect(report.applied == 1)
      #expect(report.skippedNoOp == 1)
   }

   // MARK: - Sequential dependency

   @Test func laterEditsSeeEarlierEditsResults() {
      let input = "foo bar baz"
      let edits = [
         TranscriptEdit(find: "foo", replacement: "Foo"),
         // Second edit only matches the current state ("Foo bar baz"), not the original.
         // All replacement tokens are either in `find` or in the original input, so the
         // over-reach guard allows it.
         TranscriptEdit(find: "Foo bar", replacement: "Foo, bar"),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "Foo, bar baz")
      #expect(report.applied == 2)
   }

   // MARK: - Realistic refinement patterns

   @Test func realisticFillerRemoval() {
      let input = "um so i was like you know thinking about it"
      let edits = [
         TranscriptEdit(find: "um so i was like you know", replacement: "So I was"),
         TranscriptEdit(find: "thinking about it", replacement: "thinking about it."),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "So I was thinking about it.")
      #expect(report.applied == 2)
   }

   @Test func realisticSplitWordMerge() {
      let input = "the work ing group met correct ly"
      let edits = [
         TranscriptEdit(find: "work ing", replacement: "working"),
         TranscriptEdit(find: "correct ly", replacement: "correctly"),
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "the working group met correctly")
      #expect(report.applied == 2)
   }

   @Test func realisticCapitalizationEdit() {
      let input = "i think the answer is yes"
      let edits = [
         TranscriptEdit(find: "i think", replacement: "I think")
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "I think the answer is yes")
   }

   // MARK: - Robustness

   @Test func emptyFindIsSkippedNotApplied() {
      let input = "anything"
      let edits = [TranscriptEdit(find: "", replacement: "something")]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == input)
      #expect(report.applied == 0)
      #expect(report.skippedFindNotPresent == 1)
   }

   // MARK: - Fuzzy matching (case + whitespace tolerance)

   // Apple FM sometimes capitalizes `find` strings even though the raw transcript is
   // lowercase. The applier must still locate and apply these edits.
   @Test func caseInsensitiveFuzzyFindMatches() {
      let input = "um this is a test"
      let edits = [
         // Capitalized find — wouldn't match exactly.
         TranscriptEdit(find: "Um This Is", replacement: "This is")
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "This is a test")
      #expect(report.applied == 1)
   }

   @Test func whitespaceCollapsedFuzzyFindMatches() {
      // ASR may produce single spaces, but the model's find might include a line break
      // or multiple spaces. Collapse whitespace runs when doing fuzzy matching.
      let input = "hello  world  this is a test"  // double-spaced
      let edits = [
         TranscriptEdit(find: "hello world", replacement: "Hello, world.")
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText.contains("Hello, world."))
      #expect(report.applied == 1)
   }

   @Test func exactMatchPreferredOverFuzzyWhenBothExist() {
      // When the exact match exists, don't use the fuzzy match (which might span a
      // different range).
      let input = "the cat saw the CAT run"
      let edits = [
         TranscriptEdit(find: "the CAT", replacement: "the cat")
      ]
      // Exact match for "the CAT" exists (one occurrence). The lowercase fuzzy would
      // see two matches ("the cat" and "the CAT") and count as ambiguous. We prefer
      // the exact match path which yields exactly one unambiguous match.
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.resultingText == "the cat saw the cat run")
      #expect(report.applied == 1)
   }

   @Test func processedCountEqualsInputEditCount() {
      let input = "sample text for counting"
      let edits = [
         TranscriptEdit(find: "sample", replacement: "Sample"),
         TranscriptEdit(find: "missing", replacement: "x"),  // skip: not present
         TranscriptEdit(find: "text", replacement: "text"),  // skip: no-op
         TranscriptEdit(find: "counting", replacement: "counting tokens today"),  // skip: ungrounded "today"
      ]
      let report = TranscriptEditApplier.apply(edits: edits, to: input)
      #expect(report.processed == 4)
      #expect(report.applied == 1)
   }
}
