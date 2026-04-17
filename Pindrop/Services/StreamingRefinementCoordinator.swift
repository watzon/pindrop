//
//  StreamingRefinementCoordinator.swift
//  Pindrop
//
//  Created on 2026-04-16.
//  Phase 2 rewrite on 2026-04-17 — committed/tentative split with LocalAgreement-2.
//
//  Sits between streaming transcription callbacks (from TranscriptionService) and the
//  OutputManager. Maintains a committed/tentative split of the running transcript:
//
//    - `committedText` grows monotonically. Once a chunk is committed, the text visible in
//      the user's target app for that chunk never changes.
//    - `tentativeTail` is the cleaned form of whatever Parakeet has emitted since the last
//      commit boundary. It can be replaced freely on each partial.
//    - Displayed text = `committedText + tentativeTail` (trimmed at the outer edges).
//
//  # Commit rules
//
//    - LocalAgreement-2: when the last two cumulative partials share a token-prefix of
//      length N, every token that's ≥ K=2 positions back from the trailing token of the
//      current partial is safe to commit. This is the textbook streaming-stability rule
//      shared by Whisper-Streaming and Google's Partial Rewriting work.
//    - Sentence boundary: if the last agreed token ends in `.`, `?`, or `!`, commit the
//      full agreement regardless of K — punctuation is a strong stability signal.
//    - Idle commit: if no new partial arrives within `idleCommitNanoseconds`, commit
//      the current tentative tail wholesale. Covers the end-of-thought case where the
//      user pauses mid-utterance without Parakeet's EOU firing.
//    - Final (EOU): the full emitted text is committed unconditionally.
//
//  # Deterministic cleanup
//
//  `DeterministicTranscriptCleaner` is applied to each chunk at commit time and to the
//  tentative tail each time it's recomputed. Committed text is never re-cleaned, so
//  cleanup rules that change context-dependent output (e.g. sentence-case) don't produce
//  visible churn.
//
//  # What this coordinator intentionally does NOT do (anymore)
//
//  Live LLM refinement (pause-debounce → enhancer.refine → splice) has been removed.
//  Every bug we shipped fixes for in that pipeline (duplication, "correct ly" truncation,
//  race conditions) was downstream of a single invariant violation: the LLM could rewrite
//  text the user had already seen typed. With the committed/tentative split, that becomes
//  impossible.
//
//  Post-stop holistic enhancement is still handled by AppCoordinator's
//  `runBasicPostStopEnhance` — it operates on the already-finalized text.
//

import Foundation

// MARK: - Protocols

/// Retained for a future post-stop "apply targeted edits" mode (and to keep
/// `TranscriptEditApplier`'s tests building). The coordinator itself no longer calls any
/// enhancer during live sessions.
protocol StreamingRefinementEnhancing: AnyObject, Sendable {
   func refine(fullTranscript: String) async throws -> String
}

@MainActor
protocol StreamingRefinementOutputSink: AnyObject {
   func beginStreamingInsertion()
   func updateStreamingInsertion(with text: String) async throws
   func finishStreamingInsertion(finalText: String, appendTrailingSpace: Bool) async throws
   func cancelStreamingInsertion(removeInsertedText: Bool) async
}

// MARK: - Coordinator

@MainActor
final class StreamingRefinementCoordinator {

   /// Bounded wait after session stop for the last-in-flight work to finish before we
   /// finalize. With live refinement removed, nothing is typically in flight here — kept
   /// in the API for call-site stability.
   static let defaultStopWaitNanoseconds: UInt64 = 500_000_000  // 500 ms

   /// How long after the last partial arrives before we promote the current tentative
   /// tail to committedText wholesale. Matches the "end of thought" feel of iOS dictation.
   static let defaultIdleCommitNanoseconds: UInt64 = 2_000_000_000  // 2 s

   /// LocalAgreement-N parameter. K=2 — commit a token once it's been agreed on across
   /// two partials AND there are at least two newer tokens past it.
   static let localAgreementK: Int = 2

   // MARK: Dependencies

   private weak var outputSink: StreamingRefinementOutputSink?
   private let cleaner: DeterministicTranscriptCleaner
   private let stopWaitNanoseconds: UInt64
   private let idleCommitNanoseconds: UInt64

   // MARK: Session state

   private var isSessionActive = false

   /// Latest cumulative raw transcript observed from the engine. Never trimmed on the way
   /// in — we need the original whitespace to correctly extract committed/tentative
   /// slices.
   private var rawCumulative = ""

   /// Previous partial we observed, used as the "prior" side of LocalAgreement-2.
   private var previousPartial = ""

   /// Number of leading characters of `rawCumulative` that have been committed.
   /// Monotonically non-decreasing within a session.
   private var committedRawLength = 0

   /// Cleaned, user-visible committed text. Grows by appending cleaned chunks. Never
   /// mutated once appended.
   private var committedText = ""

   /// Cleaned tentative tail — derived fresh from `rawCumulative[committedRawLength...]`
   /// on each partial. Replaced wholesale.
   private var tentativeTail = ""

   /// Last string we handed to the output sink. Used to suppress redundant updates.
   private var currentlyDisplayed = ""

   /// Sleeps for `idleCommitNanoseconds` after the last partial and commits the tentative
   /// tail if not cancelled.
   private var idleCommitTask: Task<Void, Never>?

   // MARK: Metrics

   private var stabilityMetrics = StreamingStabilityMetrics()
   private var sessionNumber = 0

   /// Always false in Phase 2+ (live refinement removed). Retained in the API so
   /// AppCoordinator's post-stop wiring doesn't need to change.
   let didLandAnyRefinement = false

   init(
      cleaner: DeterministicTranscriptCleaner = DeterministicTranscriptCleaner(),
      stopWaitNanoseconds: UInt64 = StreamingRefinementCoordinator.defaultStopWaitNanoseconds,
      idleCommitNanoseconds: UInt64 =
         StreamingRefinementCoordinator.defaultIdleCommitNanoseconds
   ) {
      self.cleaner = cleaner
      self.stopWaitNanoseconds = stopWaitNanoseconds
      self.idleCommitNanoseconds = idleCommitNanoseconds
   }

   // MARK: - Session control

   /// Starts a new session bound to `outputSink`. The coordinator drives
   /// `beginStreamingInsertion()` on the sink and all subsequent display updates.
   func beginSession(outputSink: StreamingRefinementOutputSink) {
      self.outputSink = outputSink
      isSessionActive = true
      rawCumulative = ""
      previousPartial = ""
      committedRawLength = 0
      committedText = ""
      tentativeTail = ""
      currentlyDisplayed = ""
      idleCommitTask?.cancel()
      idleCommitTask = nil
      stabilityMetrics.reset()
      sessionNumber += 1
      outputSink.beginStreamingInsertion()
      Log.transcription.debug("StreamingRefinement: session begin (v2)")
   }

   /// Handle a non-final cumulative partial from the transcriber. Updates internal state,
   /// advances the LocalAgreement-2 commit boundary if possible, and pushes the newly
   /// composed display to the output sink.
   func ingestPartial(_ text: String) async {
      guard isSessionActive else { return }
      rawCumulative = text
      stabilityMetrics.recordPartial(text)
      advanceCommitBoundary(using: text)
      previousPartial = text
      restartIdleCommitTimer()
      await applyCurrentDisplay()
   }

   /// Handle a finalized utterance from the transcriber. Parakeet's EOU is authoritative:
   /// the entire text becomes committed immediately. `accumulatedTokenIds` in Parakeet's
   /// `StreamingEouAsrManager` is session-level cumulative, so post-EOU partials continue
   /// extending `rawCumulative` — we leave `rawCumulative` and `previousPartial` in place
   /// so LocalAgreement-2 can keep working against a sensible prior.
   func ingestFinal(_ text: String) async {
      guard isSessionActive else { return }
      idleCommitTask?.cancel()
      idleCommitTask = nil
      guard !text.isEmpty else {
         // Empty EOU — clear the in-flight state without touching committedText.
         rawCumulative = ""
         committedRawLength = 0
         previousPartial = ""
         tentativeTail = ""
         await applyCurrentDisplay()
         return
      }
      rawCumulative = text
      stabilityMetrics.recordPartial(text)
      commitRawUpTo(charOffset: text.count, reason: "EOU-final")
      previousPartial = text
      await applyCurrentDisplay()
   }

   /// Wait briefly, then commit anything still tentative and return the final display
   /// text. Caller is responsible for calling `finishStreamingInsertion` on the sink if it
   /// needs to do post-processing (dictionary replacements etc.) first.
   @discardableResult
   func awaitFinalTextAndDrain() async -> String {
      guard isSessionActive else { return currentlyDisplayed }
      idleCommitTask?.cancel()
      idleCommitTask = nil
      if committedRawLength < rawCumulative.count {
         commitRawUpTo(charOffset: rawCumulative.count, reason: "drain")
         await applyCurrentDisplay()
      }
      return currentlyDisplayed
   }

   /// Convenience: drains then calls `finishStreamingInsertion` on the sink.
   @discardableResult
   func finishSession(appendTrailingSpace: Bool) async throws -> String {
      let finalText = await awaitFinalTextAndDrain()
      if let sink = outputSink, isSessionActive {
         try await sink.finishStreamingInsertion(
            finalText: finalText,
            appendTrailingSpace: appendTrailingSpace
         )
      }
      endSession()
      return finalText
   }

   /// Marks the session inactive. Safe to call multiple times. Emits the one-line
   /// stability summary the first time called for an active session.
   func endSession() {
      let wasActive = isSessionActive
      isSessionActive = false
      idleCommitTask?.cancel()
      idleCommitTask = nil
      if wasActive {
         stabilityMetrics.recordFinal(currentlyDisplayed)
         let summary = stabilityMetrics.summaryLine(sessionNumber: sessionNumber)
         Log.transcription.info("\(summary)")
      }
   }

   /// Drop the session and ask the sink to cancel its streaming insertion.
   func cancelSession(removeInsertedText: Bool) async {
      guard isSessionActive else { return }
      idleCommitTask?.cancel()
      idleCommitTask = nil
      isSessionActive = false
      if let sink = outputSink {
         await sink.cancelStreamingInsertion(removeInsertedText: removeInsertedText)
      }
   }

   // MARK: - LocalAgreement-2

   private func advanceCommitBoundary(using newPartial: String) {
      let newTokens = StreamingTokenizer.tokenize(newPartial)
      guard !newTokens.isEmpty else { return }

      let previousTokens = StreamingTokenizer.tokenize(previousPartial)
      let agreementCount = StreamingTokenizer.commonTokenPrefix(newTokens, previousTokens)
      guard agreementCount > 0 else { return }

      let lastAgreedEndsInSentence =
         StreamingTokenizer.endsWithSentenceTerminator(newTokens[agreementCount - 1])

      let commitTokenCount: Int
      if lastAgreedEndsInSentence {
         commitTokenCount = agreementCount
      } else {
         commitTokenCount = max(0, agreementCount - Self.localAgreementK)
      }
      guard commitTokenCount > 0 else { return }

      let targetEndOffset = newTokens[commitTokenCount - 1].endCharOffset
      if targetEndOffset > committedRawLength {
         commitRawUpTo(charOffset: targetEndOffset, reason: "LocalAgreement-2")
      }
   }

   /// Commit raw characters from `committedRawLength..<charOffset`, running them through
   /// the deterministic cleaner with the correct utterance-start hint before appending to
   /// `committedText`. No-op if there's nothing new to commit.
   private func commitRawUpTo(charOffset: Int, reason: String) {
      let clamped = min(max(charOffset, committedRawLength), rawCumulative.count)
      guard clamped > committedRawLength else { return }

      let startIndex = rawCumulative.index(
         rawCumulative.startIndex, offsetBy: committedRawLength
      )
      let endIndex = rawCumulative.index(rawCumulative.startIndex, offsetBy: clamped)
      let rawChunk = String(rawCumulative[startIndex..<endIndex])

      let startOfUtterance =
         committedText.isEmpty || Self.endsWithSentenceTerminator(committedText)
      let cleanedChunk = cleaner.clean(
         rawChunk,
         startOfUtterance: startOfUtterance,
         priorWord: Self.lastWord(of: committedText)
      )

      committedText += cleanedChunk
      committedRawLength = clamped

      Log.transcription.debug(
         "StreamingRefinement: committed +\(cleanedChunk.count) chars via \(reason) — committed=\(self.committedText.count), committedRawLength=\(self.committedRawLength)/\(self.rawCumulative.count)"
      )
   }

   private func recomputeTentativeTail() {
      guard committedRawLength <= rawCumulative.count else {
         tentativeTail = ""
         return
      }
      let startIndex = rawCumulative.index(
         rawCumulative.startIndex, offsetBy: committedRawLength
      )
      let rawTail = String(rawCumulative[startIndex...])
      let startOfUtterance =
         committedText.isEmpty || Self.endsWithSentenceTerminator(committedText)
      tentativeTail = cleaner.clean(
         rawTail,
         startOfUtterance: startOfUtterance,
         priorWord: Self.lastWord(of: committedText)
      )
   }

   // MARK: - Idle commit timer

   private func restartIdleCommitTimer() {
      idleCommitTask?.cancel()
      guard idleCommitNanoseconds > 0 else { return }
      let delay = idleCommitNanoseconds
      idleCommitTask = Task { @MainActor [weak self] in
         try? await Task.sleep(nanoseconds: delay)
         guard !Task.isCancelled, let self else { return }
         await self.handleIdleCommit()
      }
   }

   private func handleIdleCommit() async {
      guard isSessionActive else { return }
      idleCommitTask = nil
      guard committedRawLength < rawCumulative.count else { return }
      Log.transcription.debug(
         "StreamingRefinement: idle commit fired — committing tentative tail (\(self.rawCumulative.count - self.committedRawLength) raw chars)"
      )
      commitRawUpTo(charOffset: rawCumulative.count, reason: "idle")
      await applyCurrentDisplay()
   }

   // MARK: - Display

   private func applyCurrentDisplay() async {
      recomputeTentativeTail()
      let composed = committedText + tentativeTail
      let displayed = composed.trimmingCharacters(in: .whitespacesAndNewlines)
      guard displayed != currentlyDisplayed else { return }
      stabilityMetrics.recordDisplayUpdate(displayed)
      currentlyDisplayed = displayed
      do {
         try await outputSink?.updateStreamingInsertion(with: displayed)
      } catch {
         Log.output.error(
            "Streaming refinement display update failed: \(error.localizedDescription)")
      }
   }

   // MARK: - Helpers

   private static func endsWithSentenceTerminator(_ text: String) -> Bool {
      for character in text.reversed() {
         if character.isWhitespace { continue }
         return character == "." || character == "?" || character == "!"
      }
      return false
   }

   /// The last whitespace-delimited token of `text`, with trailing whitespace stripped.
   /// Returns nil when `text` has no word content. Used as the `priorWord` hint into
   /// `DeterministicTranscriptCleaner` so the spoken-punctuation rule can fire even when
   /// the trigger word ("period", "comma", "semicolon", …) lands as the first token of
   /// a freshly-committed chunk while its antecedent lives in already-committed text.
   private static func lastWord(of text: String) -> String? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      if let range = trimmed.rangeOfCharacter(from: .whitespaces, options: .backwards) {
         return String(trimmed[range.upperBound...])
      }
      return trimmed
   }
}

// MARK: - Tokenizer

/// Simple whitespace-delimited tokenizer that preserves per-token end offsets inside the
/// original string. Good enough for LocalAgreement-2's purposes on Parakeet output, which
/// is always English, space-separated words.
enum StreamingTokenizer {

   struct Token: Equatable {
      let text: String
      let startCharOffset: Int
      /// Offset of the first character NOT in this token, so `string[..<endCharOffset]`
      /// gives everything up through and including the token.
      let endCharOffset: Int
   }

   static func tokenize(_ text: String) -> [Token] {
      guard !text.isEmpty else { return [] }
      var tokens: [Token] = []
      var currentStart: Int? = nil
      var currentChars: [Character] = []

      for (offset, character) in text.enumerated() {
         if character.isWhitespace {
            if let start = currentStart {
               tokens.append(
                  Token(
                     text: String(currentChars),
                     startCharOffset: start,
                     endCharOffset: offset
                  )
               )
               currentStart = nil
               currentChars.removeAll(keepingCapacity: true)
            }
         } else {
            if currentStart == nil {
               currentStart = offset
            }
            currentChars.append(character)
         }
      }
      if let start = currentStart {
         tokens.append(
            Token(
               text: String(currentChars),
               startCharOffset: start,
               endCharOffset: text.count
            )
         )
      }
      return tokens
   }

   /// Number of leading tokens that are equal (case-sensitive) in both sequences.
   static func commonTokenPrefix(_ a: [Token], _ b: [Token]) -> Int {
      var count = 0
      while count < a.count && count < b.count && a[count].text == b[count].text {
         count += 1
      }
      return count
   }

   static func endsWithSentenceTerminator(_ token: Token) -> Bool {
      guard let last = token.text.last else { return false }
      return last == "." || last == "?" || last == "!"
   }
}

// MARK: - Post-stop enhancer (kept for future use)

/// Dispatches to `AIEnhancementService.enhance` for the resolved `.streamingRefinement`
/// assignment. Returns the full rewrite as a `String`. Retained through Phase 2 so that
/// future work (optional streamingEOURefinement setting, post-stop targeted-edit mode)
/// has a ready composition point. Not currently invoked by the coordinator.
final class ResolvedAssignmentEnhancer: StreamingRefinementEnhancing, @unchecked Sendable {
   private let service: AIEnhancementService
   private let assignment: ResolvedAssignment
   private let defaultPrompt: String

   init(
      service: AIEnhancementService,
      assignment: ResolvedAssignment,
      defaultPrompt: String = BuiltInPresets.liveStreamingRefinement.prompt
   ) {
      self.service = service
      self.assignment = assignment
      self.defaultPrompt = defaultPrompt
   }

   func refine(fullTranscript: String) async throws -> String {
      try await service.enhance(
         text: fullTranscript,
         assignment: assignment,
         defaultPrompt: defaultPrompt
      )
   }
}

// MARK: - OutputManager conformance

extension OutputManager: StreamingRefinementOutputSink {}
