//
//  TranscriptEditApplier.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  Pure logic for applying a list of `TranscriptEdit`s to an input string. Used by the
//  streaming refinement coordinator when the provider returns structured edits (Apple
//  Foundation Models via `@Generable`). Kept free of Apple Foundation Models imports so
//  it's unit-testable in isolation and can run on any OS version.
//
//  Behavior:
//  - Edits apply sequentially. Each edit sees the output of the previous ones.
//  - An edit whose `find` substring does not appear in the current text is skipped
//    (counted as `skippedFindNotPresent`). Rest of the batch still applies.
//  - An edit whose `find` appears in multiple places in the current text is skipped
//    (counted as `skippedFindAmbiguous`) — the prompt instructs the model to include
//    disambiguating context, and when it fails to do so, dropping is safer than
//    guessing which occurrence to replace.
//  - An edit whose replacement appears to extend beyond the input (model completion
//    of unspoken trailing alphanumeric content) is skipped as
//    `skippedFindExtendsBeyondInput`.
//  - No-op edits (`find == replacement`) are skipped as `skippedNoOp`; they don't
//    contribute to any other counter.
//

import Foundation

struct AppliedEditReport: Equatable {
   let resultingText: String
   let applied: Int
   let skippedFindNotPresent: Int
   let skippedFindAmbiguous: Int
   let skippedFindExtendsBeyondInput: Int
   let skippedNoOp: Int

   /// Convenience: true when at least one edit actually changed the text.
   var didChange: Bool { applied > 0 }

   /// Total edits that were evaluated (applied + skipped). Matches input list length.
   var processed: Int {
      applied
         + skippedFindNotPresent
         + skippedFindAmbiguous
         + skippedFindExtendsBeyondInput
         + skippedNoOp
   }
}

enum TranscriptEditApplier {

   /// Apply `edits` sequentially to `input` and return the result plus per-bucket
   /// skip counts. See file header for the skip policy.
   static func apply(
      edits: [TranscriptEdit],
      to input: String
   ) -> AppliedEditReport {
      var current = input
      var applied = 0
      var skippedFindNotPresent = 0
      var skippedFindAmbiguous = 0
      var skippedFindExtendsBeyondInput = 0
      var skippedNoOp = 0

      for edit in edits {
         // No-op fast path: `find == replacement` is wasted work, but also models
         // sometimes emit these when they think the text is already clean. Don't count
         // against applied/skipped categories; their own bucket.
         if edit.find == edit.replacement {
            skippedNoOp += 1
            continue
         }

         // `find` must appear in the current text. We try two levels of matching:
         //   1. Exact substring — the model's `find` matches verbatim (preferred).
         //   2. Whitespace-collapsed case-insensitive — the model's `find` differs only
         //      in case (Apple FM often capitalizes) or in whitespace runs (multi-space
         //      vs single-space). Range maps back to the original text so replacement
         //      happens at the intended position.
         // We do NOT fall back to fuzzy matching — that would invite the model to be
         // sloppy and risk wrong-position replacements.
         guard !edit.find.isEmpty else {
            skippedFindNotPresent += 1
            continue
         }
         let matches = locateMatches(of: edit.find, in: current)
         if matches.isEmpty {
            skippedFindNotPresent += 1
            continue
         }
         if matches.count > 1 {
            skippedFindAmbiguous += 1
            continue
         }
         let matchRange = matches[0]

         // Over-reach guard: if the replacement appends alphanumeric content that
         // wasn't part of the original input (model completion), reject. The classic
         // failure is the model emitting `find: "continue"`, `replacement: "continue today"`
         // where "today" never appeared in `input`. We check: does the replacement
         // introduce any alphanumeric token whose normalized form is absent from the
         // ORIGINAL input? If so, skip.
         if replacementIntroducesUngroundedTokens(
            find: edit.find,
            replacement: edit.replacement,
            originalInput: input
         ) {
            skippedFindExtendsBeyondInput += 1
            continue
         }

         // Apply the single replacement at the resolved range.
         current.replaceSubrange(matchRange, with: edit.replacement)
         applied += 1
      }

      return AppliedEditReport(
         resultingText: current,
         applied: applied,
         skippedFindNotPresent: skippedFindNotPresent,
         skippedFindAmbiguous: skippedFindAmbiguous,
         skippedFindExtendsBeyondInput: skippedFindExtendsBeyondInput,
         skippedNoOp: skippedNoOp
      )
   }

   // MARK: - Helpers

   /// Locate all non-overlapping matches of `needle` in `haystack`. Tries exact match
   /// first; if nothing matches, falls back to a whitespace-collapsed case-insensitive
   /// comparison so the model can be slightly loose on formatting without causing
   /// find-not-present. Returned ranges are always in the ORIGINAL haystack coordinate
   /// space so callers can `replaceSubrange` directly.
   private static func locateMatches(of needle: String, in haystack: String) -> [Range<String.Index>] {
      guard !needle.isEmpty else { return [] }

      // 1) Exact matches.
      var exact: [Range<String.Index>] = []
      var searchStart = haystack.startIndex
      while searchStart < haystack.endIndex,
         let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex)
      {
         exact.append(range)
         searchStart = range.upperBound
      }
      if !exact.isEmpty { return exact }

      // 2) Whitespace-collapsed case-insensitive fallback. Build two parallel
      //    representations of the haystack: the normalized string (lower-cased, with
      //    runs of whitespace replaced by a single space) plus an array mapping each
      //    normalized char back to its original-haystack index. Then run the same
      //    search on the normalized needle and map matches back to the original range.
      let (normalizedHaystack, haystackOriginalIndex) = normalizeWithIndexMap(haystack)
      let (normalizedNeedle, _) = normalizeWithIndexMap(needle)
      guard !normalizedHaystack.isEmpty, !normalizedNeedle.isEmpty else { return [] }

      var fuzzy: [Range<String.Index>] = []
      var normSearchStart = normalizedHaystack.startIndex
      while normSearchStart < normalizedHaystack.endIndex,
         let normRange = normalizedHaystack.range(
            of: normalizedNeedle, range: normSearchStart..<normalizedHaystack.endIndex)
      {
         let normLowerOffset = normalizedHaystack.distance(
            from: normalizedHaystack.startIndex, to: normRange.lowerBound)
         let normUpperOffset = normalizedHaystack.distance(
            from: normalizedHaystack.startIndex, to: normRange.upperBound)
         guard normLowerOffset < haystackOriginalIndex.count else { break }
         let originalLowerOffset = haystackOriginalIndex[normLowerOffset]
         // For the upper bound, use the original index of the char AFTER the last
         // matched normalized char (clamped to the haystack's end).
         let originalUpperOffset: Int
         if normUpperOffset < haystackOriginalIndex.count {
            originalUpperOffset = haystackOriginalIndex[normUpperOffset]
         } else {
            originalUpperOffset = haystack.count
         }
         let lower = haystack.index(haystack.startIndex, offsetBy: originalLowerOffset)
         let upper = haystack.index(
            haystack.startIndex,
            offsetBy: max(originalUpperOffset, originalLowerOffset + 1)
         )
         fuzzy.append(lower..<upper)
         normSearchStart = normRange.upperBound
      }
      return fuzzy
   }

   /// Lowercase the text and collapse whitespace runs to a single space. Returns the
   /// normalized string plus a parallel array mapping each normalized character offset
   /// back to the corresponding offset in the ORIGINAL input. Whitespace runs map to
   /// the index of the first whitespace char.
   private static func normalizeWithIndexMap(_ text: String) -> (String, [Int]) {
      var normalized = ""
      var map: [Int] = []
      var lastWasSpace = false
      for (offset, char) in text.enumerated() {
         if char.isWhitespace {
            if !lastWasSpace && !normalized.isEmpty {
               normalized.append(" ")
               map.append(offset)
               lastWasSpace = true
            }
            // Drop any additional whitespace in a run.
         } else {
            for lower in char.lowercased() {
               normalized.append(lower)
               map.append(offset)
            }
            lastWasSpace = false
         }
      }
      // Trim a trailing single space.
      if normalized.last == " " {
         normalized.removeLast()
         map.removeLast()
      }
      // Trim a leading single space.
      if normalized.first == " " {
         normalized.removeFirst()
         map.removeFirst()
      }
      return (normalized, map)
   }

   /// Whether the replacement's alphanumeric tokens include at least one that's missing
   /// from both the `find` span and the original input. Prevents the model from silently
   /// typing completions the speaker never actually said (e.g. `continue` -> `continue today`
   /// where "today" never appeared). Two common legitimate refinements are explicitly
   /// allowed:
   ///   - Pure re-formatting: lowercase-alphanumeric content of `find` == replacement's.
   ///     Covers capitalization fixes, punctuation insertion, and split-word merges like
   ///     `"correct ly"` -> `"correctly"` where the letters are the same, just regrouped.
   ///   - Token subset: every replacement token already appears in `find` (removing a
   ///     filler word while keeping the rest).
   private static func replacementIntroducesUngroundedTokens(
      find: String,
      replacement: String,
      originalInput: String
   ) -> Bool {
      // Allow any edit whose lowercase-alnum-only collapse matches the find's. Split-word
      // merges, capitalization fixes, and punctuation insertion all pass this check.
      let findAlnum = lowercasedAlphanumeric(in: find)
      let replacementAlnum = lowercasedAlphanumeric(in: replacement)
      if findAlnum == replacementAlnum { return false }

      let findTokens = Set(alphanumericTokens(in: find))
      let replacementTokens = alphanumericTokens(in: replacement)
      let inputTokens = Set(alphanumericTokens(in: originalInput))
      for token in replacementTokens {
         if findTokens.contains(token) { continue }
         if inputTokens.contains(token) { continue }
         if token.count <= 1 { continue }
         return true
      }
      return false
   }

   private static func lowercasedAlphanumeric(in text: String) -> String {
      text.lowercased().filter { $0.isLetter || $0.isNumber }
   }

   private static func alphanumericTokens(in text: String) -> [String] {
      var tokens: [String] = []
      var current = ""
      for char in text.lowercased() {
         if char.isLetter || char.isNumber {
            current.append(char)
         } else if !current.isEmpty {
            tokens.append(current)
            current = ""
         }
      }
      if !current.isEmpty { tokens.append(current) }
      return tokens
   }
}
