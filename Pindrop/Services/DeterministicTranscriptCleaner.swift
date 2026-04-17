//
//  DeterministicTranscriptCleaner.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  Pure rule-based cleanup pass applied to the tentative tail of a streaming transcript.
//  Runs *between* the raw ASR partial and the text shown to the user, so the display picks
//  up obvious mechanical fixes (filler removal, capitalization) without involving an LLM.
//
//  Design rules (from the live-refinement shape-up plan):
//
//    - Commutative and low-risk. Applied fresh to each raw tentative tail — the committed
//      prefix is never re-cleaned, so the cleaner doesn't need to be idempotent across
//      repeated invocations on its own output.
//    - Conservative. If a rule would need to "be clever" — guess at context, punctuate
//      mid-clause — we don't do it. Only transforms that are obvious wins without false
//      positives make it in.
//    - Whole-token only. Filler removal and `i` → `I` never touch text mid-word.
//
//  The unit tests for this struct double as the spec.
//

import Foundation

struct DeterministicTranscriptCleaner: Sendable {

   /// Case-insensitive standalone filler tokens removed outright when they appear as
   /// whole words. `you know` is intentionally excluded — the false-positive rate on
   /// legitimate uses ("I think you know the answer") is too high for a deterministic
   /// pass.
   static let fillerTokens: Set<String> = [
      "um", "uh", "erm", "hmm", "hm",
   ]

   /// Characters that terminate a sentence for the purpose of sentence-case restoration.
   private static let sentenceTerminators: Set<Character> = [".", "?", "!"]

   init() {}

   /// Run the full deterministic cleanup pipeline on `text`, returning the cleaned form.
   /// Safe on empty input. Preserves the caller's leading/trailing whitespace so the
   /// coordinator can concatenate cleaned tails back onto committed text without losing
   /// boundary spaces.
   ///
   /// `startOfUtterance` hints the sentence-case pass: when `true` (default), the first
   /// alphabetic character in `text` is capitalized. When `false`, the coordinator is
   /// passing us a continuation chunk that lives mid-sentence — only interior sentence
   /// transitions (after `.`, `?`, `!`) trigger capitalization, not the leading letter.
   ///
   /// `priorWord` is the last whitespace-delimited token of the already-committed text
   /// that precedes `text`. It lets the spoken-punctuation rule fire even when a phrase
   /// like "period" arrives as the first token of a newly-committed chunk (e.g. after an
   /// idle commit swallowed "works" into the committed prefix).
   func clean(
      _ text: String,
      startOfUtterance: Bool = true,
      priorWord: String? = nil
   ) -> String {
      guard !text.isEmpty else { return text }
      var result = text
      result = Self.mergeSplitSuffixes(result)
      result = Self.normalizeCompoundNumberWords(result)
      result = Self.removeFillers(result)
      result = Self.replaceSpokenPunctuation(result, priorWord: priorWord)
      result = Self.capitalizeStandaloneI(result)
      result = Self.applySentenceCase(result, startOfUtterance: startOfUtterance)
      return result
   }

   // MARK: - Rules

   /// Strip filler tokens (`um`, `uh`, `erm`, `hmm`, `hm`) when they appear as standalone
   /// words delimited purely by whitespace (or string boundaries). Conservative on
   /// purpose: a filler hugged by punctuation (`well, um, we`) is left alone so we don't
   /// produce visible `,,` double-comma artifacts. One side of whitespace is swallowed so
   /// mid-sentence removals don't leave double spaces.
   ///
   /// Intentionally NOT removed:
   ///   - `like` (disambiguating vs. comparison/verb usage requires context).
   ///   - `you know` (too many legitimate occurrences).
   ///   - Fillers that are part of a larger word (`hummingbird`, `umbrella`).
   ///   - Fillers adjacent to punctuation (`well, um, we should`) — too-risky context.
   static func removeFillers(_ text: String) -> String {
      guard !text.isEmpty else { return text }

      var out = ""
      var index = text.startIndex
      while index < text.endIndex {
         let charStart = index
         let scalar = text[index]

         if scalar.isLetter {
            // Walk the current word.
            var wordEnd = index
            while wordEnd < text.endIndex, text[wordEnd].isLetter {
               wordEnd = text.index(after: wordEnd)
            }
            let word = String(text[charStart..<wordEnd])
            let lowered = word.lowercased()

            let prevIsBoundary = out.isEmpty || (out.last?.isWhitespace == true)
            let nextIsBoundary = wordEnd == text.endIndex || text[wordEnd].isWhitespace

            if fillerTokens.contains(lowered) && prevIsBoundary && nextIsBoundary {
               // Drop the filler. Swallow one adjacent whitespace: prefer the trailing
               // space so leading capitalization still sees a word boundary; otherwise
               // swallow the preceding space.
               if wordEnd < text.endIndex, text[wordEnd].isWhitespace {
                  index = text.index(after: wordEnd)
               } else if !out.isEmpty, out.last?.isWhitespace == true {
                  out.removeLast()
                  index = wordEnd
               } else {
                  index = wordEnd
               }
               continue
            } else {
               out.append(contentsOf: word)
               index = wordEnd
               continue
            }
         }

         out.append(scalar)
         index = text.index(after: index)
      }
      return out
   }

   /// Capitalize the pronoun `i` when it appears as a standalone token (i.e. surrounded by
   /// non-letter characters). Leaves real words starting with `i` alone.
   static func capitalizeStandaloneI(_ text: String) -> String {
      guard !text.isEmpty else { return text }

      var out: [Character] = []
      out.reserveCapacity(text.count)

      let chars = Array(text)
      var i = 0
      while i < chars.count {
         let c = chars[i]
         let prev: Character? = i > 0 ? chars[i - 1] : nil
         let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

         let isStandaloneI =
            c == "i"
            && (prev == nil || !prev!.isLetter)
            && (next == nil || !next!.isLetter)

         if isStandaloneI {
            out.append("I")
         } else {
            out.append(c)
         }
         i += 1
      }
      return String(out)
   }

   /// Capitalize the first alphabetic character of the overall text (when
   /// `startOfUtterance` is true) and the first alphabetic character after any sentence
   /// terminator (`.`, `?`, `!`) followed by whitespace. All other letter positions are
   /// left untouched.
   static func applySentenceCase(_ text: String, startOfUtterance: Bool = true) -> String {
      guard !text.isEmpty else { return text }

      var out = Array(text)
      var needsCapital = startOfUtterance
      var sawTerminator = false

      for index in 0..<out.count {
         let c = out[index]
         if sawTerminator && c.isWhitespace {
            // Keep sawTerminator flag until we actually find the next letter.
            continue
         }
         if sawTerminator && c.isLetter {
            needsCapital = true
            sawTerminator = false
         }

         if needsCapital && c.isLetter {
            out[index] = Character(c.uppercased())
            needsCapital = false
         }

         if sentenceTerminators.contains(c) {
            sawTerminator = true
         }
      }
      return String(out)
   }

   // MARK: - Spoken punctuation

   /// Words that, when immediately followed by "period" / "comma", strongly suggest the
   /// following word is a noun, not a punctuation command. Populated conservatively:
   /// covers determiners/articles/possessives plus the handful of common noun
   /// collocations ("grace period", "time period", "Oxford comma", etc.).
   private static let spokenPunctuationNounBlocklist: Set<String> = [
      // Determiners / articles / possessives — almost always precede noun usage.
      "the", "a", "an", "this", "that", "these", "those", "my", "your",
      "his", "her", "our", "their", "its", "no", "any", "some", "each",
      // Prepositions commonly found before "period" (the noun).
      "of", "in", "during", "for", "after", "before", "until", "since",
      "within", "throughout", "over",
      // Noun collocations: "grace period", "time period", "trial period", etc.
      "grace", "time", "trial", "waiting", "transition", "probationary",
      "incubation", "menstrual", "gestation", "relief",
      // "Oxford comma", "serial comma" collocations.
      "oxford", "serial",
      // Descriptive adjectives that frequently precede "period" as a noun.
      "long", "short", "brief", "whole", "entire", "same", "next", "last",
      "previous", "new", "old", "given", "set", "single", "critical",
      "transitional", "historical", "dark", "golden", "classical",
   ]

   /// Replace spoken-punctuation words with their marks. Handles trailing usage
   /// ("that's all period"), mid-text usage ("pretty well period but it seems…"), and
   /// chunk-boundary usage where the punctuation word is the very first token of the
   /// text but the immediately-prior word lives in already-committed output (passed via
   /// `priorWord`). Replacement is gated by `spokenPunctuationNounBlocklist` so phrases
   /// like "during the period of" or "grace period" stay alone.
   static func replaceSpokenPunctuation(_ text: String, priorWord: String? = nil)
      -> String
   {
      guard !text.isEmpty else { return text }

      // Longer phrases first so "exclamation point" wins over "exclamation" alone.
      let rules: [(phrase: [String], mark: String)] = [
         (["question", "mark"], "?"),
         (["exclamation", "point"], "!"),
         (["exclamation", "mark"], "!"),
         (["period"], "."),
         (["comma"], ","),
         (["semicolon"], ";"),
         (["semi", "colon"], ";"),  // ASR sometimes fragments "semicolon"
         (["colon"], ":"),
      ]

      let tokens = tokenizeWithOffsets(text)
      guard !tokens.isEmpty else { return text }

      // Normalize priorWord for blocklist lookup: strip trailing punctuation and
      // lowercase. If the prior word itself ends in a sentence terminator, treat it as
      // "already punctuated" — don't add more punctuation on top.
      let priorWordLowered: String? = {
         guard let raw = priorWord?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
         else { return nil }
         if let last = raw.last,
            (last.isPunctuation || ".,;:?!".contains(last))
         {
            return nil  // prior token isn't a clean word — skip replacement at boundary
         }
         return raw.lowercased()
      }()

      var replacements: [(start: Int, end: Int, mark: String)] = []

      var i = 0
      while i < tokens.count {
         var matched = false
         for rule in rules {
            guard i + rule.phrase.count <= tokens.count else { continue }
            let window = (i..<i + rule.phrase.count).map {
               tokens[$0].text.lowercased()
            }
            guard window == rule.phrase else { continue }

            // Determine the "effective prior word" for the blocklist check. If there's a
            // token before the phrase in THIS text, use that; otherwise fall back to the
            // coordinator-supplied prior word.
            let priorForBlocklist: String?
            if i > 0 {
               priorForBlocklist = tokens[i - 1].text.lowercased()
            } else {
               priorForBlocklist = priorWordLowered
            }

            // Require a prior word to exist. A lone punctuation word at the very start
            // with no prior context (e.g., user begins dictation with "Period") stays
            // alone.
            guard let prior = priorForBlocklist else { continue }
            if spokenPunctuationNounBlocklist.contains(prior) { continue }

            // Splice: when there's an in-text prior token, absorb the whitespace between
            // it and the phrase so "well period" becomes "well." (not "well ."). When
            // the prior word is external, swallow leading whitespace of `text` so
            // "[committed=works] [chunk= period]" becomes "[chunk=.]".
            let start: Int
            if i > 0 {
               start = tokens[i - 1].endCharOffset
            } else {
               start = 0
            }
            let end = tokens[i + rule.phrase.count - 1].endCharOffset
            replacements.append((start: start, end: end, mark: rule.mark))

            i += rule.phrase.count
            matched = true
            break
         }
         if !matched { i += 1 }
      }

      guard !replacements.isEmpty else { return text }

      var result = text
      for replacement in replacements.reversed() {
         let lower = result.index(result.startIndex, offsetBy: replacement.start)
         let upper = result.index(result.startIndex, offsetBy: replacement.end)
         result.replaceSubrange(lower..<upper, with: replacement.mark)
      }
      return result
   }

   // MARK: - Compound cardinal numbers

   /// Convert compound cardinals 20–99 to digits: "twenty five" → "25", "twenty-five"
   /// → "25". Only replaces multi-token forms; standalone single-word numbers ("one",
   /// "twenty") are left alone because they overwhelmingly appear as quantity words in
   /// natural prose ("one day", "twenty years"), and replacing them breaks more than it
   /// fixes.
   static func normalizeCompoundNumberWords(_ text: String) -> String {
      guard !text.isEmpty else { return text }

      let tens: [String: Int] = [
         "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
         "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
      ]
      let ones: [String: Int] = [
         "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
         "six": 6, "seven": 7, "eight": 8, "nine": 9,
      ]

      // First pass: collapse hyphenated forms by splitting on the hyphen, running the
      // same rule, and re-joining. "twenty-five" → "twenty five" → "25".
      let hyphenatedNormalized = text.replacingOccurrences(
         of: #"(?i)\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)-(one|two|three|four|five|six|seven|eight|nine)\b"#,
         with: "$1 $2",
         options: .regularExpression
      )

      let tokens = tokenizeWithOffsets(hyphenatedNormalized)
      guard !tokens.isEmpty else { return text }

      var result = ""
      var index = 0
      var lastCopiedEnd = 0

      while index < tokens.count {
         let token = tokens[index]
         let lower = token.text.lowercased()

         if index + 1 < tokens.count,
            let tensValue = tens[lower],
            let onesValue = ones[tokens[index + 1].text.lowercased()]
         {
            // Append any whitespace/punctuation between the prior copied position and
            // the start of this number.
            let prefixStart = hyphenatedNormalized.index(
               hyphenatedNormalized.startIndex, offsetBy: lastCopiedEnd)
            let prefixEnd = hyphenatedNormalized.index(
               hyphenatedNormalized.startIndex, offsetBy: token.startCharOffset)
            result += String(hyphenatedNormalized[prefixStart..<prefixEnd])

            result += "\(tensValue + onesValue)"
            lastCopiedEnd = tokens[index + 1].endCharOffset
            index += 2
         } else {
            index += 1
         }
      }

      // Copy the tail of the normalized string.
      let tailStart = hyphenatedNormalized.index(
         hyphenatedNormalized.startIndex, offsetBy: lastCopiedEnd)
      result += String(hyphenatedNormalized[tailStart...])
      return result
   }

   // MARK: - Split-word suffix merging

   /// Merge `[root] [suffix]` into `[rootsuffix]` when the suffix is one of the common
   /// ASR-fragmentation endings (`ly`, `ing`, `ed`). Both tokens must be lowercase and
   /// the prior token must end in a letter — protects against proper nouns ("Mr Ed")
   /// and already-correct splits ("got ED").
   static func mergeSplitSuffixes(_ text: String) -> String {
      guard !text.isEmpty else { return text }

      let suffixes: Set<String> = ["ly", "ing", "ed"]
      let tokens = tokenizeWithOffsets(text)
      guard tokens.count >= 2 else { return text }

      var result = ""
      var index = 0
      var lastCopiedEnd = 0

      while index < tokens.count {
         let token = tokens[index]
         if index + 1 < tokens.count {
            let next = tokens[index + 1]
            let nextLower = next.text.lowercased()

            let isLowercaseRoot =
               token.text == token.text.lowercased() && !token.text.isEmpty
               && (token.text.last?.isLetter ?? false)
            let isLowercaseSuffix =
               next.text == next.text.lowercased() && suffixes.contains(nextLower)

            if isLowercaseRoot && isLowercaseSuffix {
               // Copy untouched prefix from lastCopiedEnd..<tokenStart.
               let prefixStart = text.index(text.startIndex, offsetBy: lastCopiedEnd)
               let prefixEnd = text.index(text.startIndex, offsetBy: token.startCharOffset)
               result += String(text[prefixStart..<prefixEnd])

               result += token.text + next.text
               lastCopiedEnd = next.endCharOffset
               index += 2
               continue
            }
         }
         index += 1
      }

      // Copy tail.
      let tailStart = text.index(text.startIndex, offsetBy: lastCopiedEnd)
      result += String(text[tailStart...])
      return result
   }

   // MARK: - Tokenization helper (shared)

   /// Lightweight tokenizer that returns contiguous non-whitespace runs with original
   /// character offsets. Intentionally does NOT split on punctuation — a trailing comma
   /// stays attached to the token, which is what the caller usually wants for the
   /// "word at end of text" checks.
   fileprivate struct OffsetToken {
      let text: String
      let startCharOffset: Int
      let endCharOffset: Int
   }

   fileprivate static func tokenizeWithOffsets(_ text: String) -> [OffsetToken] {
      var tokens: [OffsetToken] = []
      var currentStart: Int? = nil
      var currentChars: [Character] = []
      for (offset, character) in text.enumerated() {
         if character.isWhitespace {
            if let start = currentStart {
               tokens.append(
                  OffsetToken(
                     text: String(currentChars),
                     startCharOffset: start,
                     endCharOffset: offset
                  )
               )
               currentStart = nil
               currentChars.removeAll(keepingCapacity: true)
            }
         } else {
            if currentStart == nil { currentStart = offset }
            currentChars.append(character)
         }
      }
      if let start = currentStart {
         tokens.append(
            OffsetToken(
               text: String(currentChars),
               startCharOffset: start,
               endCharOffset: text.count
            )
         )
      }
      return tokens
   }
}
