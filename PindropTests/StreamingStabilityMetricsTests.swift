//
//  StreamingStabilityMetricsTests.swift
//  Pindrop
//
//  Created on 2026-04-17.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct StreamingStabilityMetricsTests {

   @Test func upwrZeroWhenPartialsStrictlyExtend() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("hello")
      metrics.recordPartial("hello world")
      metrics.recordPartial("hello world today")
      metrics.recordFinal("hello world today")

      #expect(metrics.unstablePartialWordRatio == 0)
      #expect(metrics.unseenPartialSegmentRevisions == 0)
      #expect(metrics.finalWordCount == 3)
   }

   @Test func upwrCountsRemovedTokens() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("hello word")     // "word" is a transcriber stumble
      metrics.recordPartial("hello world")    // corrected — "word" no longer present
      metrics.recordFinal("hello world")

      // Final tokens: {hello, world}. Partials had both plus "word".
      // UPWR = |{word}| / |{hello, world}| = 1 / 2 = 0.5
      #expect(metrics.unstablePartialWordRatio == 0.5)
   }

   @Test func upsrCountsRevisionsOfPreviousPartial() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("the quick")
      metrics.recordPartial("the quick brown")
      // Revision: new partial doesn't extend prior — "quick" was replaced.
      metrics.recordPartial("the slow brown fox")

      #expect(metrics.unseenPartialSegmentRevisions == 1)
   }

   @Test func retypeBytesAccumulateAcrossDisplayUpdates() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordDisplayUpdate("hello")
      metrics.recordDisplayUpdate("help")
      metrics.recordDisplayUpdate("helpful")
      metrics.recordFinal("helpful")

      // "" → "hello": common prefix "" → 0 backspaces + 5 retypes = 5
      // "hello" → "help": common prefix "hel" → 2 backspaces + 1 retype = 3
      // "help" → "helpful": common prefix "help" → 0 backspaces + 3 retypes = 3
      // Total = 11 retype characters across 1 word ("helpful").
      #expect(metrics.retypeCharacterCount == 11)
      #expect(metrics.retypeBytesPerWord == 11.0)
   }

   @Test func emptyFinalProducesZeroMetricsWithoutCrashing() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("um")
      metrics.recordFinal("")

      #expect(metrics.unstablePartialWordRatio == 0)
      #expect(metrics.retypeBytesPerWord == 0)
      #expect(metrics.finalWordCount == 0)
   }

   @Test func summaryLineFormatMatchesPlanContract() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("hello world")
      metrics.recordDisplayUpdate("hello world")
      metrics.recordFinal("hello world")

      let line = metrics.summaryLine(sessionNumber: 4)
      #expect(line.hasPrefix("StreamingStability: session 4 words=2"))
      #expect(line.contains("UPWR="))
      #expect(line.contains("UPSR="))
      #expect(line.contains("retypeBytesPerWord="))
   }

   @Test func tokensAreCaseAndPunctuationInsensitive() {
      let tokens = StreamingStabilityMetrics.tokens(in: "Hello, World! Hello.")
      #expect(tokens == ["hello", "world", "hello"])
   }

   @Test func resetClearsAllCounters() {
      var metrics = StreamingStabilityMetrics()
      metrics.recordPartial("hello")
      metrics.recordDisplayUpdate("hello")
      metrics.recordFinal("hello")
      metrics.reset()

      metrics.recordFinal("next")
      #expect(metrics.unseenPartialSegmentRevisions == 0)
      #expect(metrics.retypeCharacterCount == 0)
      #expect(metrics.unstablePartialWordRatio == 0)
   }
}
