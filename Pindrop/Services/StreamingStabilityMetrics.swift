//
//  StreamingStabilityMetrics.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  Counters that quantify how much the live streaming display churned during a session.
//  Emitted at `StreamingRefinementCoordinator.endSession()` so future architecture changes
//  (committed/tentative split, deterministic cleanup, SpeechTranscriber backend, …) can be
//  measured against a baseline instead of eyeballed.
//
//  Metrics (from the streaming-stability literature; see Apple SpeechAnalyzer WWDC25,
//  Google Partial Rewriting, Whisper-Streaming's LocalAgreement-n):
//
//    - UPWR (Unstable Partial Word Ratio): tokens that appeared in intermediate partials
//      but are missing from the final transcript, divided by final token count. Lower is
//      better; a run that never rewrote history has UPWR = 0.
//    - UPSR (Unseen Partial Segment Revision Rate): number of times a new partial did
//      *not* strictly extend the prior partial — i.e. an already-displayed segment was
//      rewritten. Raw count, not a ratio. Lower is better.
//    - retypeBytesPerWord: total diff-engine backspace + retype character count divided
//      by final transcript word count. Proxies how much real keyboard noise the user saw.
//      Lower is better.
//

import Foundation

struct StreamingStabilityMetrics: Sendable {

   /// Tokens (case-folded, alnum-only) seen at any point in a partial during this session.
   private var partialTokens: Set<String> = []

   /// The prior partial text, used to detect revisions of already-displayed segments.
   private var lastPartial: String = ""

   /// The prior displayed text on the output sink, used to count backspace + retype bytes
   /// from the diff engine's perspective.
   private var lastDisplayed: String = ""

   /// Number of times a new partial did not strictly extend the previous one, i.e. it
   /// rewrote a previously-displayed token. Plain count.
   private(set) var unseenPartialSegmentRevisions: Int = 0

   /// Sum of backspace + retype character counts inferred from successive `display`
   /// updates. Populated by `recordDisplayUpdate(_:)`.
   private(set) var retypeCharacterCount: Int = 0

   /// Final transcript of the session, set at stop. Empty until `recordFinal(_:)` is
   /// called.
   private var finalText: String = ""

   mutating func reset() {
      partialTokens.removeAll()
      lastPartial = ""
      lastDisplayed = ""
      unseenPartialSegmentRevisions = 0
      retypeCharacterCount = 0
      finalText = ""
   }

   /// Record the arrival of a cumulative partial transcript. Feeds both UPWR (via token
   /// set union) and UPSR (via prefix comparison against the prior partial).
   mutating func recordPartial(_ text: String) {
      let tokens = Self.tokens(in: text)
      for token in tokens {
         partialTokens.insert(token)
      }

      // UPSR: a new partial is a "revision" of already-displayed text iff it doesn't
      // extend the previous partial's token prefix. Strict extension = new partial's
      // tokens start with the old partial's tokens.
      if !lastPartial.isEmpty {
         let previous = Self.tokens(in: lastPartial)
         if !Self.isTokenPrefix(previous, of: tokens) {
            unseenPartialSegmentRevisions += 1
         }
      }
      lastPartial = text
   }

   /// Record the committed text at session stop. Drives UPWR's denominator.
   mutating func recordFinal(_ text: String) {
      finalText = text
   }

   /// Record what the output sink is now showing, after any diff-engine retype. The
   /// difference between the prior display and the new display (common-prefix decomposition)
   /// is charged to `retypeCharacterCount`: backspaces for characters dropped from the
   /// prior display, retypes for the new suffix.
   mutating func recordDisplayUpdate(_ displayed: String) {
      let commonPrefixCount = lastDisplayed.commonPrefix(with: displayed).count
      let backspaced = lastDisplayed.count - commonPrefixCount
      let retyped = displayed.count - commonPrefixCount
      retypeCharacterCount += max(0, backspaced) + max(0, retyped)
      lastDisplayed = displayed
   }

   // MARK: - Derived

   var finalTokenCount: Int {
      Self.tokens(in: finalText).count
   }

   var finalWordCount: Int {
      finalText
         .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
         .filter { !$0.isEmpty }
         .count
   }

   /// UPWR = |partialTokens \ finalTokens| / |finalTokens|. Zero when the final transcript
   /// has no tokens (avoids division by zero and trivially reports "no instability").
   var unstablePartialWordRatio: Double {
      let finalTokens = Set(Self.tokens(in: finalText))
      guard !finalTokens.isEmpty else { return 0 }
      let dropped = partialTokens.subtracting(finalTokens)
      return Double(dropped.count) / Double(finalTokens.count)
   }

   var retypeBytesPerWord: Double {
      let words = finalWordCount
      guard words > 0 else { return 0 }
      return Double(retypeCharacterCount) / Double(words)
   }

   /// The single log line emitted at session stop. Format matches the plan's contract so
   /// the metrics are greppable from logs.
   func summaryLine(sessionNumber: Int) -> String {
      String(
         format:
            "StreamingStability: session %d words=%d UPWR=%.2f UPSR=%d retypeBytesPerWord=%.2f",
         sessionNumber,
         finalWordCount,
         unstablePartialWordRatio,
         unseenPartialSegmentRevisions,
         retypeBytesPerWord
      )
   }

   // MARK: - Helpers

   /// Tokenize into the same case-folded, alnum-only form the coordinator uses elsewhere
   /// — keeps "hello," and "hello" equivalent for counting purposes.
   static func tokens(in text: String) -> [String] {
      var out: [String] = []
      var current = ""
      for character in text {
         let folded = String(character)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
         if let scalar = folded.unicodeScalars.first,
            CharacterSet.alphanumerics.contains(scalar) {
            current.append(Character(String(scalar)))
         } else if !current.isEmpty {
            out.append(current)
            current = ""
         }
      }
      if !current.isEmpty { out.append(current) }
      return out
   }

   /// True when `prefix` is a (not necessarily strict) token-wise prefix of `full`.
   private static func isTokenPrefix(_ prefix: [String], of full: [String]) -> Bool {
      guard prefix.count <= full.count else { return false }
      for (index, token) in prefix.enumerated() {
         if full[index] != token { return false }
      }
      return true
   }
}
