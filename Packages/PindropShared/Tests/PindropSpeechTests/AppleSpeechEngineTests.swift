//
//  AppleSpeechEngineTests.swift
//  PindropSpeechTests
//
//  Created on 2026-10-04.
//

import AVFoundation
import Foundation
import Speech
import Testing
@testable import PindropSpeech

/// Issue #85: on-device recognition starts a new transcription after each pause.
/// The result sequences below are the ones `SFSpeechRecognizer` reported for
/// synthesized speech with 3 s pauses (start and end are audio times in seconds).
@Suite("AppleSpeechUtteranceAccumulator")
struct AppleSpeechUtteranceAccumulatorTests {
    @Test func isEmptyWithoutResults() {
        #expect(AppleSpeechUtteranceAccumulator().text == "")
    }

    @Test func keepsEveryUtteranceBeforeAPause() {
        var sut = AppleSpeechUtteranceAccumulator()

        sut.add(text: "I went to the store", start: 0.0, end: 2.58)
        sut.add(text: "Then I walked home", start: 5.64, end: 8.43)
        sut.add(text: "We talked about the project", start: 11.49, end: 14.55)

        #expect(sut.text == "I went to the store Then I walked home We talked about the project")
    }

    @Test func doesNotRepeatTheLastUtteranceWhenTheFinalResultRepeatsIt() {
        var sut = AppleSpeechUtteranceAccumulator()

        // With silence at the end, the final result repeats the last utterance.
        sut.add(text: "I went to the store", start: 0.0, end: 2.58)
        sut.add(text: "Then I walked home", start: 5.64, end: 7.53)
        sut.add(text: "Then I walked home", start: 5.64, end: 7.53)

        #expect(sut.text == "I went to the store Then I walked home")
    }

    @Test func keepsTheSamePhraseWhenItIsSpokenTwice() {
        var sut = AppleSpeechUtteranceAccumulator()

        sut.add(text: "Yes", start: 0.0, end: 0.4)
        sut.add(text: "Yes", start: 3.5, end: 3.9)

        #expect(sut.text == "Yes Yes")
    }

    @Test func aSingleFinalResultIsReturnedUnchanged() {
        var sut = AppleSpeechUtteranceAccumulator()

        sut.add(text: "I went to the store then I walked home", start: 0.0, end: 5.46)

        #expect(sut.text == "I went to the store then I walked home")
    }

    @Test func aNewerVersionReplacesTheUtterancesItOverlaps() {
        var sut = AppleSpeechUtteranceAccumulator()

        // Partial results grow one utterance.
        sut.add(text: "I went", start: 0.0, end: 0.6)
        sut.add(text: "I went to the store", start: 0.0, end: 2.58)
        sut.add(text: "Then I", start: 5.64, end: 6.0)
        #expect(sut.text == "I went to the store Then I")

        // A result with the full text replaces all utterances that it covers.
        sut.add(text: "I went to the store then I walked home", start: 0.0, end: 8.43)
        #expect(sut.text == "I went to the store then I walked home")
    }

    @Test func ignoresEmptyResults() {
        var sut = AppleSpeechUtteranceAccumulator()

        sut.add(text: "I went to the store", start: 0.0, end: 2.58)
        sut.add(text: "  ", start: 5.0, end: 5.0)
        sut.add(text: "", start: nil, end: nil)

        #expect(sut.text == "I went to the store")
    }

    @Test func aResultWithoutWordTimingFollowsTheTimedUtterances() {
        var sut = AppleSpeechUtteranceAccumulator()

        sut.add(text: "I went to the store", start: 0.0, end: 2.58)
        sut.add(text: "Then I walked home", start: nil, end: nil)

        #expect(sut.text == "I went to the store Then I walked home")
    }

    @Test func untimedResultsKeepOnlyTheNewestText() {
        var sut = AppleSpeechUtteranceAccumulator()

        // Without word timing a new utterance and a newer version look the same.
        sut.add(text: "I went", start: nil, end: nil)
        sut.add(text: "I went to the store", start: nil, end: nil)

        #expect(sut.text == "I went to the store")
    }
}

// MARK: - Integration (real on-device recognition) — opt-in only

/// Needs the on-device speech model for en-US. Run with:
///   PINDROP_RUN_INTEGRATION_TESTS=1 swift test --package-path Packages/PindropShared \
///     --filter AppleSpeechEngineIntegrationTests
@MainActor
@Suite(
    "AppleSpeechEngine (integration, on-device recognition)",
    .enabled(
        if: ProcessInfo.processInfo.environment["PINDROP_RUN_INTEGRATION_TESTS"] == "1",
        "Apple Speech recognition tests are disabled by default. Run with PINDROP_RUN_INTEGRATION_TESTS=1."
    )
)
struct AppleSpeechEngineIntegrationTests {
    @Test func transcriptKeepsTheSpeechBeforeEachPause() async throws {
        let recognizer = try #require(SFSpeechRecognizer(locale: Locale(identifier: "en-US")))
        try #require(recognizer.isAvailable && recognizer.supportsOnDeviceRecognition)
        let buffer = try SpeechSynthesisTestSupport.synthesizeSpeechBuffer(
            "I went to the store this morning and bought some apples. [[slnc 3000]] "
                + "Then I walked home through the park and called my friend. [[slnc 3000]] "
                + "We talked about the new project that starts next week. [[slnc 4000]]"
        )

        let transcript = try await AppleSpeechEngine()
            .performRecognition(using: recognizer, buffer: buffer)
            .lowercased()

        for keyword in ["apples", "park", "project"] {
            #expect(transcript.contains(keyword), "Missing '\(keyword)' in: '\(transcript)'")
        }
        #expect(
            transcript.components(separatedBy: "project").count == 2,
            "The last utterance must appear once: '\(transcript)'"
        )
    }
}
