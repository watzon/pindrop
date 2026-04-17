//
//  AIEnhancementResponseSanitizerTests.swift
//  PindropTests
//
//  Created on 2026-04-17.
//
//  Spec for `AIEnhancementService.stripResponsePreamble` — the belt-and-suspenders step
//  that removes conversational preambles the LLM sometimes adds despite the
//  `<output_contract>` telling it not to. These tests double as the list of known
//  preamble patterns the streaming post-stop path guards against.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct AIEnhancementResponseSanitizerTests {

   @Test func stripsHereIsPreamble() {
      let input = "Here is your updated transcription: this is the real text."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "this is the real text.")
   }

   @Test func stripsHeresContractionPreamble() {
      let input = "Here's the cleaned text: actual content."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "actual content.")
   }

   @Test func stripsBelowIsPreamble() {
      let input = "Below is the cleaned transcript: real content here."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "real content here.")
   }

   @Test func stripsLabelStylePreamble() {
      let input = "Cleaned transcript: hello world."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "hello world.")
   }

   @Test func stripsPlainTranscriptLabel() {
      let input = "Transcript: the meeting went well."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "the meeting went well.")
   }

   @Test func stripsAcknowledgmentOpener() {
      let input = "Sure! the cleaned version is here."
      let result = AIEnhancementService.stripResponsePreamble(input)
      #expect(result == "the cleaned version is here.")
   }

   @Test func stripsSurroundingQuotes() {
      let input = "\"this is the text\""
      #expect(AIEnhancementService.stripResponsePreamble(input) == "this is the text")
   }

   @Test func stripsCompoundPreamble() {
      // Model adds both an acknowledgment AND a label.
      let input = "Sure! Here is the cleaned transcription: real content."
      #expect(AIEnhancementService.stripResponsePreamble(input) == "real content.")
   }

   @Test func leavesCleanResponseUnchanged() {
      let input = "this is a clean response with no preamble."
      #expect(AIEnhancementService.stripResponsePreamble(input) == input)
   }

   @Test func leavesResponseStartingWithHereButNotAPreamble() {
      // "Here you go" without colon isn't a preamble — and this phrasing legitimately
      // belongs in a transcript ("Here I come, ready or not.").
      let input = "Here I come, ready or not."
      #expect(AIEnhancementService.stripResponsePreamble(input) == input)
   }

   @Test func trimsWhitespace() {
      let input = "\n\n  hello world  \n"
      #expect(AIEnhancementService.stripResponsePreamble(input) == "hello world")
   }

   @Test func preservesOriginalWhenStrippingEmpties() {
      // If stripping leaves empty text, return the original so we don't lose content.
      let input = "Sure!"
      #expect(AIEnhancementService.stripResponsePreamble(input) == "Sure!")
   }

   @Test func handlesEmptyInput() {
      #expect(AIEnhancementService.stripResponsePreamble("") == "")
   }

   @Test func isIdempotentOnAlreadyCleanOutput() {
      let input = "Here is the cleaned text: actual content."
      let once = AIEnhancementService.stripResponsePreamble(input)
      let twice = AIEnhancementService.stripResponsePreamble(once)
      #expect(once == twice)
   }

   @Test func caseInsensitive() {
      let input = "HERE IS THE UPDATED TRANSCRIPTION: shouted content"
      #expect(AIEnhancementService.stripResponsePreamble(input) == "shouted content")
   }
}
