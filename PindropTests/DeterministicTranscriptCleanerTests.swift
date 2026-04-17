//
//  DeterministicTranscriptCleanerTests.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  These tests are the spec for what the deterministic cleanup layer does. If a transform
//  isn't covered here, the live streaming path shouldn't be doing it.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct DeterministicTranscriptCleanerTests {

   private let cleaner = DeterministicTranscriptCleaner()

   // MARK: - Filler removal

   @Test func removesStandaloneFillerInMiddleOfSentence() {
      #expect(cleaner.clean("so um i was thinking") == "So I was thinking")
   }

   @Test func removesMultipleFillers() {
      #expect(cleaner.clean("uh so uh we should um go") == "So we should go")
   }

   @Test func removesTrailingFiller() {
      #expect(cleaner.clean("hello um") == "Hello")
   }

   @Test func removesLeadingFiller() {
      #expect(cleaner.clean("um hello") == "Hello")
   }

   @Test func doesNotRemoveFillerInsideWord() {
      // "umbrella" contains "um" — must not be truncated to "brella".
      #expect(cleaner.clean("the umbrella is wet") == "The umbrella is wet")
   }

   @Test func doesNotRemoveFillerThatIsntWhitespaceDelimited() {
      // "humble" contains "um" mid-word; "hum" is technically a filler but here it's a
      // prefix — must not be touched.
      #expect(cleaner.clean("be humble") == "Be humble")
   }

   @Test func isCaseInsensitiveForFillers() {
      #expect(cleaner.clean("OK Um we should go") == "OK we should go")
   }

   @Test func leavesFillerAloneWhenAdjacentToPunctuation() {
      // Conservative: removing `um` here would leave `Well,, we should go`, visibly
      // worse than the input. The rule skips fillers hugged by punctuation.
      #expect(cleaner.clean("well, um, we should go") == "Well, um, we should go")
   }

   @Test func doesNotRemoveLike() {
      // `like` is intentionally excluded — too many legitimate usages.
      #expect(cleaner.clean("i like this") == "I like this")
   }

   @Test func doesNotRemoveYouKnow() {
      // `you know` is intentionally excluded.
      #expect(cleaner.clean("you know what i mean") == "You know what I mean")
   }

   // MARK: - Standalone "i" → "I"

   @Test func capitalizesStandaloneI() {
      #expect(cleaner.clean("when i arrive i will call") == "When I arrive I will call")
   }

   @Test func doesNotCapitalizeIInsideWord() {
      #expect(cleaner.clean("it is inside") == "It is inside")
   }

   @Test func capitalizesIFollowedByPunctuation() {
      #expect(cleaner.clean("yes i, of course") == "Yes I, of course")
   }

   @Test func capitalizesIAtEndOfText() {
      #expect(cleaner.clean("that's not me it's i") == "That's not me it's I")
   }

   // MARK: - Sentence case

   @Test func capitalizesFirstLetterOfText() {
      #expect(cleaner.clean("hello world") == "Hello world")
   }

   @Test func capitalizesAfterPeriod() {
      #expect(cleaner.clean("hello. world") == "Hello. World")
   }

   @Test func capitalizesAfterQuestionMark() {
      #expect(cleaner.clean("is it? yes") == "Is it? Yes")
   }

   @Test func capitalizesAfterExclamation() {
      #expect(cleaner.clean("wow! that's great") == "Wow! That's great")
   }

   @Test func leavesInteriorLettersAlone() {
      // Words in the middle of a sentence must not be recapitalized.
      #expect(cleaner.clean("this is a TEST case") == "This is a TEST case")
   }

   @Test func handlesMultipleSentences() {
      #expect(
         cleaner.clean("hello world. this is a test. how are you?")
            == "Hello world. This is a test. How are you?"
      )
   }

   // MARK: - Combinations

   @Test func combinedFillerRemovalCapitalizationSentenceCase() {
      let input = "um i think we should go. uh it's getting late."
      #expect(cleaner.clean(input) == "I think we should go. It's getting late.")
   }

   @Test func preservesEmptyString() {
      #expect(cleaner.clean("") == "")
   }

   @Test func preservesSingleWhitespace() {
      // A lone space is important for tentative-tail boundary preservation — don't strip it.
      #expect(cleaner.clean(" ") == " ")
   }

   @Test func handlesLeadingWhitespace() {
      #expect(cleaner.clean(" hello world") == " Hello world")
   }

   // MARK: - startOfUtterance flag (coordinator integration)

   @Test func continuationChunkDoesNotCapitalizeLeadingLetter() {
      // This is how the coordinator hands us a mid-sentence tentative tail: committed
      // already says "Hello", and the raw tail is " world". We must not uppercase `w`.
      #expect(cleaner.clean(" world", startOfUtterance: false) == " world")
   }

   @Test func continuationChunkStillCapitalizesAfterInternalTerminators() {
      // A continuation chunk can still contain a sentence boundary internally —
      // capitalization after `. ` fires regardless of the utterance-start hint.
      #expect(
         cleaner.clean(" end of thought. new one begins", startOfUtterance: false)
            == " end of thought. New one begins"
      )
   }

   @Test func continuationChunkCanStillRemoveFillers() {
      #expect(cleaner.clean(" um continue", startOfUtterance: false) == " continue")
   }

   // MARK: - Trailing spoken punctuation

   @Test func replacesTrailingPeriod() {
      #expect(cleaner.clean("that's all period") == "That's all.")
   }

   @Test func replacesTrailingQuestionMark() {
      #expect(cleaner.clean("is it true question mark") == "Is it true?")
   }

   @Test func replacesTrailingExclamationPoint() {
      #expect(cleaner.clean("we did it exclamation point") == "We did it!")
   }

   @Test func replacesTrailingExclamationMark() {
      #expect(cleaner.clean("wow exclamation mark") == "Wow!")
   }

   @Test func replacesTrailingComma() {
      #expect(cleaner.clean("hello comma") == "Hello,")
   }

   @Test func doesNotReplacePeriodMidSentence() {
      // "period" in the middle of prose stays — too ambiguous to be safe.
      #expect(
         cleaner.clean("during the period of enlightenment")
            == "During the period of enlightenment"
      )
   }

   @Test func doesNotReplaceLonePeriodAsOnlyToken() {
      // The user is probably mid-partial, not dictating a punctuation command.
      #expect(cleaner.clean("period") == "Period")
   }

   @Test func replacesMidSentencePeriodBetweenClauses() {
      // This is the real-world case: a user dictates "…pretty well period but it seems…"
      // and expects the period to become a sentence boundary with the following clause
      // capitalized.
      #expect(
         cleaner.clean("it seems to be working pretty well period but it seems as though")
            == "It seems to be working pretty well. But it seems as though"
      )
   }

   @Test func replacesMidSentenceCommaBetweenClauses() {
      #expect(
         cleaner.clean("hello comma how are you doing today")
            == "Hello, how are you doing today"
      )
   }

   @Test func leavesNounUsageAfterTheAlone() {
      #expect(
         cleaner.clean("during the period of enlightenment there was peace")
            == "During the period of enlightenment there was peace"
      )
   }

   @Test func leavesNounUsageAfterCollocation() {
      // "grace period" and "time period" are noun collocations — don't split them.
      #expect(cleaner.clean("there is a grace period of fourteen days")
         == "There is a grace period of fourteen days")
      #expect(cleaner.clean("during that time period nothing happened")
         == "During that time period nothing happened")
   }

   @Test func leavesOxfordCommaAlone() {
      #expect(
         cleaner.clean("i prefer the oxford comma in lists")
            == "I prefer the oxford comma in lists"
      )
   }

   @Test func replacesMidSentenceQuestionMark() {
      #expect(
         cleaner.clean("is this right question mark i think so")
            == "Is this right? I think so"
      )
   }

   // MARK: - Compound cardinal numbers

   @Test func convertsSpaceSeparatedCompoundNumber() {
      #expect(cleaner.clean("i have twenty five apples") == "I have 25 apples")
   }

   @Test func convertsHyphenatedCompoundNumber() {
      #expect(cleaner.clean("she is twenty-five years old") == "She is 25 years old")
   }

   @Test func convertsMultipleCompoundNumbers() {
      #expect(
         cleaner.clean("ages twenty five and thirty seven are noted")
            == "Ages 25 and 37 are noted"
      )
   }

   @Test func leavesSingleWordNumberAlone() {
      // "twenty" standalone is ambiguous — often a quantity, leave it.
      #expect(cleaner.clean("about twenty people") == "About twenty people")
   }

   @Test func doesNotMangleNonNumberCompound() {
      // A non-numeric word that happens to start with "twenty" shouldn't trigger.
      #expect(
         cleaner.clean("the twenty century was famous") == "The twenty century was famous"
      )
   }

   // MARK: - Split-word suffix merging

   @Test func mergesCorrectLyIntoCorrectly() {
      #expect(cleaner.clean("please spell this correct ly") == "Please spell this correctly")
   }

   @Test func mergesWorkIngIntoWorking() {
      #expect(cleaner.clean("they are work ing today") == "They are working today")
   }

   @Test func mergesWorkEdIntoWorked() {
      #expect(cleaner.clean("he work ed all day") == "He worked all day")
   }

   @Test func doesNotMergeWhenPriorTokenIsCapitalized() {
      // "Mr Ed" is a proper noun pattern — don't collapse to "MrEd".
      #expect(cleaner.clean("Mr Ed arrived") == "Mr Ed arrived")
   }

   @Test func doesNotMergeWhenSuffixIsCapitalized() {
      #expect(cleaner.clean("work ED today") == "Work ED today")
   }

   @Test func doesNotMergeWhenSuffixIsNotInWhitelist() {
      // "on", "off", "up" are real words, not ASR suffix fragmentation.
      #expect(cleaner.clean("run on forever") == "Run on forever")
   }

   // MARK: - Semicolon and colon

   @Test func replacesTrailingSemicolon() {
      #expect(cleaner.clean("first thought semicolon") == "First thought;")
   }

   @Test func replacesSplitSemicolonFromASR() {
      // Parakeet sometimes emits "semicolon" as "semi colon" across two tokens.
      #expect(cleaner.clean("first thought semi colon") == "First thought;")
   }

   @Test func replacesTrailingColon() {
      #expect(cleaner.clean("here is the list colon") == "Here is the list:")
   }

   @Test func replacesMidSentenceSemicolon() {
      #expect(
         cleaner.clean("apples are red semicolon oranges are orange")
            == "Apples are red; oranges are orange"
      )
   }

   // MARK: - Chunk-boundary priorWord handoff
   //
   // When the coordinator commits a chunk whose first token is a punctuation word
   // ("period" after "works" was already committed via idle-commit), the cleaner
   // must know what word preceded the chunk to make the right call. The coordinator
   // passes it via the `priorWord` parameter.

   @Test func replacesPunctuationAtStartOfChunkWhenPriorWordIsValid() {
      #expect(
         cleaner.clean(" period", startOfUtterance: false, priorWord: "works")
            == "."
      )
   }

   @Test func skipsPunctuationAtChunkStartWhenPriorWordIsBlocklisted() {
      // Committed prefix ends with "the" — "period" is almost certainly a noun.
      #expect(
         cleaner.clean(" period", startOfUtterance: false, priorWord: "the")
            == " period"
      )
   }

   @Test func skipsPunctuationAtChunkStartWhenPriorWordEndsInPunctuation() {
      // Committed prefix already ends with a sentence terminator — don't stack another.
      #expect(
         cleaner.clean(" period", startOfUtterance: false, priorWord: "done.")
            == " period"
      )
   }

   @Test func chunkStartCommaReplacedWhenPriorWordIsValid() {
      #expect(
         cleaner.clean(" comma then he spoke", startOfUtterance: false, priorWord: "hello")
            == ", then he spoke"
      )
   }

   @Test func chunkStartSemicolonReplacedWhenPriorWordIsValid() {
      #expect(
         cleaner.clean(" semicolon next clause", startOfUtterance: false, priorWord: "thought")
            == "; next clause"
      )
   }

   // MARK: - Combined pipeline

   @Test func allTransformsComposeInFullPipeline() {
      let input = "um i have twenty five apples and correct ly count them period"
      #expect(
         cleaner.clean(input)
            == "I have 25 apples and correctly count them."
      )
   }
}
