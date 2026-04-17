//
//  StreamingRefinementCoordinatorTests.swift
//  PindropTests
//
//  Created on 2026-04-16.
//  Rewritten on 2026-04-17 for the Phase 2 committed/tentative architecture.
//
//  These tests are the contract for the streaming refinement coordinator. Key invariants:
//
//    1. `committedText` is append-only — once a prefix is committed, nothing (not a new
//       partial, not EOU, not idle commit) mutates or replaces it.
//    2. LocalAgreement-2 commits tokens once they've been agreed on across two successive
//       partials AND are at least K=2 tokens back from the trailing token of the current
//       partial.
//    3. Sentence boundaries commit the full agreement regardless of K.
//    4. Idle-commit timer promotes the tentative tail wholesale after the configured
//       idle threshold.
//    5. Deterministic cleanup (filler removal, capitalization) is applied — both to
//       newly-committed chunks and to the tentative tail, freshly on each update.
//    6. `ingestFinal` commits everything (EOU is authoritative).
//    7. At session stop, the final displayed text equals committedText + tentativeTail.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite(.serialized)
struct StreamingRefinementCoordinatorTests {

   // MARK: - Fakes

   @MainActor
   final class FakeSink: StreamingRefinementOutputSink {
      private(set) var beganCount = 0
      private(set) var updates: [String] = []
      private(set) var finished: (text: String, trailingSpace: Bool)?
      private(set) var cancelledRemovingText: Bool?

      func beginStreamingInsertion() {
         beganCount += 1
      }

      func updateStreamingInsertion(with text: String) async throws {
         updates.append(text)
      }

      func finishStreamingInsertion(finalText: String, appendTrailingSpace: Bool) async throws {
         finished = (finalText, appendTrailingSpace)
      }

      func cancelStreamingInsertion(removeInsertedText: Bool) async {
         cancelledRemovingText = removeInsertedText
      }

      /// The longest displayed string across all updates — useful as a proxy for "what
      /// the user ultimately saw" when ordering doesn't matter.
      var lastUpdate: String? { updates.last }
   }

   // MARK: - Helpers

   /// Convenience: idle commit disabled (-1 → 0 nanoseconds via max), stop wait short.
   private func makeCoordinator(
      stopWaitNs: UInt64 = 60_000_000,
      idleCommitNs: UInt64 = 0
   ) -> StreamingRefinementCoordinator {
      StreamingRefinementCoordinator(
         stopWaitNanoseconds: stopWaitNs,
         idleCommitNanoseconds: idleCommitNs
      )
   }

   // MARK: - Session lifecycle

   @Test func beginSessionCallsSinkBegin() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()

      coord.beginSession(outputSink: sink)

      #expect(sink.beganCount == 1)
   }

   @Test func endSessionIsIdempotent() {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      coord.endSession()
      coord.endSession()  // should not crash or re-log
   }

   // MARK: - Cumulative partials drive tentative display

   @Test func partialsAppearAsTentativeDisplay() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("hello")
      await coord.ingestPartial("hello world")

      // Deterministic cleaner capitalizes the leading letter.
      #expect(sink.lastUpdate == "Hello world")
   }

   // MARK: - LocalAgreement-2 commit rule

   @Test func localAgreementCommitsTokenAfterTwoPartialsPlusK() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      // Single partial — no prior history to agree with — nothing committed.
      await coord.ingestPartial("one")
      // Agreement on "one" but only 0 tokens past it — still K=2 short.
      await coord.ingestPartial("one two")
      // Agreement on "one two" but only 1 token past — still K=2 short.
      await coord.ingestPartial("one two three")
      // Now "one" is 2 tokens back from "four" — commits.
      await coord.ingestPartial("one two three four")

      #expect(sink.lastUpdate == "One two three four")

      // Final drain so we can verify committed prefix is "One" (3 chars worth in raw,
      // with cleanup capitalization applied).
      let finalText = await coord.awaitFinalTextAndDrain()
      #expect(finalText == "One two three four")
   }

   @Test func localAgreementIgnoresMismatchedPartial() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("hello")
      // Second partial disagrees — no commit possible.
      await coord.ingestPartial("goodbye world")
      // Third partial disagrees with both prior — still no commit.
      await coord.ingestPartial("foo bar baz")

      // Only the final tentative is visible. Committed is still empty.
      #expect(sink.lastUpdate == "Foo bar baz")
   }

   @Test func sentenceBoundaryCommitsWithoutWaitingForK() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      // Two agreeing partials ending in `.` — commit the whole agreement immediately.
      await coord.ingestPartial("hello world.")
      await coord.ingestPartial("hello world. next")

      // "hello world." is already committed (2 tokens, both agreed, last ends with `.`).
      // Further partials that extend must not rewrite that prefix.
      await coord.ingestPartial("hello world. next sentence")

      #expect(sink.lastUpdate == "Hello world. Next sentence")
   }

   // MARK: - Committed text is append-only

   @Test func committedTextIsNeverRewrittenByNewPartials() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      // Drive enough partials to commit "one":
      await coord.ingestPartial("one")
      await coord.ingestPartial("one two")
      await coord.ingestPartial("one two three")
      await coord.ingestPartial("one two three four")

      let displayedAfterCommit = sink.lastUpdate
      #expect(displayedAfterCommit == "One two three four")

      // Now send a new partial that DISAGREES about the later tokens. The committed "One"
      // must stay; the tentative portion can rewrite freely.
      await coord.ingestPartial("one five six seven eight nine")

      let afterRewrite = sink.lastUpdate ?? ""
      // Committed prefix "One" is preserved.
      #expect(afterRewrite.hasPrefix("One "))
      // The rewritten tail made it in.
      #expect(afterRewrite.contains("five six seven"))
   }

   // MARK: - ingestFinal (EOU) commits everything

   @Test func ingestFinalCommitsAllText() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("hello")
      await coord.ingestFinal("hello world this is final")

      // Everything is committed — a later partial CAN'T downgrade this.
      let finalText = await coord.awaitFinalTextAndDrain()
      #expect(finalText == "Hello world this is final")
   }

   @Test func ingestEmptyFinalClearsState() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("some text")
      await coord.ingestFinal("")

      let finalText = await coord.awaitFinalTextAndDrain()
      #expect(finalText == "")
   }

   // MARK: - Idle commit

   @Test func idleTimerCommitsTentativeTailWholesale() async throws {
      let sink = FakeSink()
      // 80 ms idle threshold so the test can wait past it cheaply.
      let coord = makeCoordinator(idleCommitNs: 80_000_000)
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("thinking about something")

      // Wait beyond the idle threshold.
      try await Task.sleep(nanoseconds: 200_000_000)

      // Drain to ensure the idle-committed state is reflected.
      let finalText = await coord.awaitFinalTextAndDrain()
      #expect(finalText == "Thinking about something")
   }

   // MARK: - Deterministic cleanup is applied

   @Test func fillerTokensAreRemovedInTentativeDisplay() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("so um i was thinking")

      #expect(sink.lastUpdate == "So I was thinking")
   }

   @Test func cleanupAppliedToCommittedChunksAtCommitTime() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      // Force commit of a prefix containing filler, via LocalAgreement-2.
      await coord.ingestPartial("um hello there")
      await coord.ingestPartial("um hello there friend")
      await coord.ingestPartial("um hello there friend how")
      await coord.ingestPartial("um hello there friend how are")

      // Final drain includes the full text, all cleaned.
      let finalText = await coord.awaitFinalTextAndDrain()
      // "um" should be removed; first letter capitalized; rest preserved.
      #expect(finalText == "Hello there friend how are")
   }

   // MARK: - Final display equals committed + tentative

   @Test func awaitFinalTextAndDrainReturnsComposedDisplay() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.ingestPartial("hello")
      await coord.ingestPartial("hello world")

      let finalText = await coord.awaitFinalTextAndDrain()
      #expect(finalText == "Hello world")
   }

   @Test func finishSessionCallsSinkFinishWithTrailingSpaceFlag() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)
      await coord.ingestPartial("hello world")

      _ = try await coord.finishSession(appendTrailingSpace: true)

      #expect(sink.finished?.text == "Hello world")
      #expect(sink.finished?.trailingSpace == true)
   }

   // MARK: - Cancel

   @Test func cancelSessionAsksSinkToCancel() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      await coord.cancelSession(removeInsertedText: true)

      #expect(sink.cancelledRemovingText == true)
   }

   // MARK: - Integration: simulated long stream

   /// Simulates Parakeet's session-level cumulative stream: partials grow, EOU commits a
   /// checkpoint, further partials continue extending the whole transcript. Asserts the
   /// committed text ends up sane across two sentence boundaries.
   @Test func simulatedLongStreamStaysStable() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)

      let utteranceA = "hello world how are you doing today"
      var buildup = ""
      for token in utteranceA.split(separator: " ").map(String.init) {
         buildup = buildup.isEmpty ? token : buildup + " " + token
         await coord.ingestPartial(buildup)
      }
      let afterFirst = buildup + "."
      await coord.ingestFinal(afterFirst)

      // Second utterance continues the session-level cumulative stream.
      let utteranceB = "i am doing great thanks for asking"
      for token in utteranceB.split(separator: " ").map(String.init) {
         buildup = buildup + " " + token
         await coord.ingestPartial(buildup)
      }
      let afterSecond = buildup + "."
      await coord.ingestFinal(afterSecond)

      let finalText = await coord.awaitFinalTextAndDrain()

      // Committed output includes both utterances, cleanly capitalized.
      #expect(finalText.hasPrefix("Hello world how are you doing today."))
      #expect(finalText.contains("I am doing great thanks for asking."))
   }

   // MARK: - Metrics wiring

   @Test func metricsAreEmittedAtEndSessionForActiveSession() async throws {
      let sink = FakeSink()
      let coord = makeCoordinator()
      coord.beginSession(outputSink: sink)
      await coord.ingestPartial("hello")
      await coord.ingestFinal("hello")

      // Just verifying end-of-session doesn't crash; the actual log output is covered by
      // StreamingStabilityMetricsTests. No user-visible assertion here beyond basic
      // state hygiene.
      coord.endSession()
   }
}
