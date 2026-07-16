//
//  OverlayStreamingSinkTests.swift
//  PindropTests
//
//  Created on 2026-06-05.
//
//  Contract tests for the overlay streaming sink: live text goes to the transcript
//  state (never the target app), the final text is output exactly once at finish, and
//  the overlay always collapses — on finish, cancel, and even when the final output
//  throws.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct OverlayStreamingSinkTests {

    private struct OutputFailure: Error {}

    @MainActor
    private final class OutputRecorder {
        private(set) var outputs: [String] = []
        var result: OutputManager.OutputResult = .pasted()
        var error: Error?
        private(set) var fallbackCount = 0
        private(set) var fallbackResults: [OutputManager.OutputResult] = []

        func makeSink(transcriptState: LiveTranscriptState) -> OverlayStreamingSink {
            OverlayStreamingSink(
                transcriptState: transcriptState,
                finalOutput: { [weak self] text in
                    guard let self else { return .pasted() }
                    self.outputs.append(text)
                    if let error = self.error { throw error }
                    return self.result
                },
                onClipboardFallback: { [weak self] result in
                    self?.fallbackCount += 1
                    self?.fallbackResults.append(result)
                }
            )
        }
    }

    // MARK: - Live updates feed the overlay only

    @Test func beginActivatesTranscriptAndClearsPriorText() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.updateStreamingInsertion(committed: "Hello", tentative: " world")
        sink.beginStreamingInsertion()

        #expect(state.phase == .streaming)
        #expect(state.committedText.isEmpty)
        #expect(state.tentativeText.isEmpty)
        #expect(recorder.outputs.isEmpty)
    }

    @Test func updatesPublishCommittedAndTentativeSplit() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.updateStreamingInsertion(committed: "Hello", tentative: " world")

        #expect(state.committedText == "Hello")
        #expect(state.tentativeText == " world")
        #expect(state.displayText == "Hello world")
        #expect(recorder.outputs.isEmpty)
    }

    // MARK: - Finish

    @Test func finishOutputsFinalTextExactlyOnceAndCollapsesOverlay() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.updateStreamingInsertion(committed: "Hello", tentative: " world")
        try await sink.finishStreamingInsertion(finalText: "Hello world", appendTrailingSpace: false)

        #expect(recorder.outputs == ["Hello world"])
        #expect(state.phase == .inactive)
        #expect(state.committedText.isEmpty)
    }

    @Test func finishAppendsTrailingSpaceWhenRequested() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.finishStreamingInsertion(finalText: "Hello", appendTrailingSpace: true)

        #expect(recorder.outputs == ["Hello "])
    }

    @Test func finishWithEmptyTextCollapsesOverlayWithoutOutput() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.updateStreamingInsertion(committed: "noise", tentative: "")
        try await sink.finishStreamingInsertion(finalText: "", appendTrailingSpace: true)

        #expect(recorder.outputs.isEmpty)
        #expect(state.phase == .inactive)
    }

    @Test func finishCollapsesOverlayAndRethrowsWhenOutputFails() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        recorder.error = OutputFailure()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        await #expect(throws: OutputFailure.self) {
            try await sink.finishStreamingInsertion(finalText: "Hello", appendTrailingSpace: false)
        }
        #expect(state.phase == .inactive)
    }

    @Test func clipboardFallbackResultFiresCallback() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        recorder.result = .copiedToClipboard(reason: .accessibilityUnavailable)
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.finishStreamingInsertion(finalText: "Hello", appendTrailingSpace: false)

        #expect(recorder.fallbackCount == 1)
        #expect(recorder.fallbackResults.first?.clipboardFallbackReason == .accessibilityUnavailable)
    }

    @Test func pastedResultDoesNotFireFallback() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.finishStreamingInsertion(finalText: "Hello", appendTrailingSpace: false)

        #expect(recorder.fallbackCount == 0)
    }

    // MARK: - Cancel

    @Test func cancelDiscardsOverlayWithoutOutput() async throws {
        let state = LiveTranscriptState()
        let recorder = OutputRecorder()
        let sink = recorder.makeSink(transcriptState: state)

        sink.beginStreamingInsertion()
        try await sink.updateStreamingInsertion(committed: "Hello", tentative: " world")
        await sink.cancelStreamingInsertion()

        #expect(recorder.outputs.isEmpty)
        #expect(state.phase == .inactive)
        #expect(state.committedText.isEmpty)
    }

    // MARK: - LiveTranscriptState transitions

    @Test func enhancingPhaseKeepsTextAndIgnoresInactiveTransition() async throws {
        let state = LiveTranscriptState()

        state.begin()
        state.update(committed: "Hello", tentative: " world")
        state.beginEnhancing()

        #expect(state.phase == .enhancing)
        #expect(state.committedText == "Hello")

        // beginEnhancing from inactive is a no-op.
        state.end()
        state.beginEnhancing()
        #expect(state.phase == .inactive)
    }

    @Test func updatesAreIgnoredWhenInactive() async throws {
        let state = LiveTranscriptState()

        state.update(committed: "ghost", tentative: "")

        #expect(state.committedText.isEmpty)
        #expect(state.phase == .inactive)
    }
}
