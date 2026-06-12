//
//  LiveTranscriptState.swift
//  Pindrop
//
//  Created on 2026-06-05.
//
//  Observable model for the live-transcript overlay shown inside the floating
//  indicators while a streaming dictation session is active. Owned by AppCoordinator
//  and shared across all indicator presenters so switching indicator type mid-session
//  keeps the transcript.
//
//  Lifecycle: `begin()` when the streaming session's output sink stands up,
//  `update(committed:tentative:)` on each coordinator display update,
//  `beginEnhancing()` while the post-stop LLM enhancement runs (text stays visible,
//  views show a progress affordance), and `end()` when the session finishes, cancels,
//  or fails — views collapse back to their non-transcript shapes.
//

import Foundation

@MainActor
final class LiveTranscriptState: ObservableObject {

    enum Phase: Equatable {
        /// No streaming session — indicators render their existing recording UI.
        case inactive
        /// Live partials are flowing; transcript text updates continuously.
        case streaming
        /// Recording stopped; post-stop enhancement is rewriting the final text.
        case enhancing
    }

    @Published private(set) var phase: Phase = .inactive
    @Published private(set) var committedText = ""
    @Published private(set) var tentativeText = ""

    var isActive: Bool { phase != .inactive }

    /// The composed display string, joined identically to what the coordinator shows.
    var displayText: String {
        StreamingRefinementCoordinator.composeDisplay(
            committed: committedText,
            tentative: tentativeText
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func begin() {
        phase = .streaming
        committedText = ""
        tentativeText = ""
    }

    func update(committed: String, tentative: String) {
        guard phase != .inactive else { return }
        committedText = committed
        tentativeText = tentative
    }

    func beginEnhancing() {
        guard phase == .streaming else { return }
        phase = .enhancing
    }

    func end() {
        phase = .inactive
        committedText = ""
        tentativeText = ""
    }
}
