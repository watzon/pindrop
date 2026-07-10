//
//  OverlayStreamingSink.swift
//  Pindrop
//
//  Created on 2026-06-05.
//
//  StreamingRefinementOutputSink that renders the live transcript in Pindrop's own
//  floating-indicator overlay instead of typing into the target app. The target app
//  receives the final text exactly once, via a single atomic paste when the session
//  finishes — there is no live keystroke synthesis, no diffing, and nothing to undo
//  on cancel.
//
//  Final insertion is injected as a closure (`finalOutput`) rather than a direct
//  OutputManager dependency so the sink is trivially testable; AppCoordinator wires it
//  to `outputManager.output(_:)`, which routes by the user's output mode (directInsert
//  → paste, clipboard → copy/paste flow).
//

import Foundation

@MainActor
final class OverlayStreamingSink: StreamingRefinementOutputSink {

    private let transcriptState: LiveTranscriptState
    private let finalOutput: @MainActor (String) async throws -> OutputManager.OutputResult
    private let onClipboardFallback: (@MainActor () -> Void)?

    /// Result of the most recent successful `finishStreamingInsertion` call.
    /// Cleared at the start of each finish attempt so callers can distinguish
    /// "no output yet" from a prior session's result.
    private(set) var lastOutputResult: OutputManager.OutputResult?

    init(
        transcriptState: LiveTranscriptState,
        finalOutput: @escaping @MainActor (String) async throws -> OutputManager.OutputResult,
        onClipboardFallback: (@MainActor () -> Void)? = nil
    ) {
        self.transcriptState = transcriptState
        self.finalOutput = finalOutput
        self.onClipboardFallback = onClipboardFallback
    }

    func beginStreamingInsertion() {
        transcriptState.begin()
    }

    func updateStreamingInsertion(committed: String, tentative: String) async throws {
        transcriptState.update(committed: committed, tentative: tentative)
    }

    func finishStreamingInsertion(finalText: String, appendTrailingSpace: Bool) async throws {
        // The overlay always collapses, even when the final output throws — the caller's
        // error path must not leave a stranded transcript panel on screen.
        defer { transcriptState.end() }
        lastOutputResult = nil
        guard !finalText.isEmpty else { return }

        let output = appendTrailingSpace ? finalText + " " : finalText
        let result = try await finalOutput(output)
        lastOutputResult = result
        if result.didCopyToClipboard {
            onClipboardFallback?()
        }
    }

    func cancelStreamingInsertion() async {
        transcriptState.end()
    }
}
