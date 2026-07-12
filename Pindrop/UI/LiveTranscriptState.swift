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

    /// Upper bound for the floating-indicator viewport string. Three lines of
    /// ~14 pt body in the streaming card fit well under this; rendering cost
    /// stays proportional to the visible tail rather than the full session.
    static let displayTailCharacterLimit = 360

    @Published private(set) var phase: Phase = .inactive
    @Published private(set) var committedText = ""
    @Published private(set) var tentativeText = ""

    /// Composed, trimmed display string — authoritative cache of the full live
    /// transcript join. Callers that need the complete text (final output
    /// mirrors, accessibility) read this instead of recomposing.
    private(set) var displayText = ""

    /// Bounded suffix of `displayText` for the three-line floating-indicator
    /// viewport. Styling and layout work only this tail.
    private(set) var displayTail = ""

    var isActive: Bool { phase != .inactive }

    func begin() {
        clearDisplayCaches()
        phase = .streaming
        committedText = ""
        tentativeText = ""
    }

    func update(committed: String, tentative: String) {
        guard phase != .inactive else { return }
        // Streaming sinks can re-publish identical snapshots; skip equality so
        // indicator bodies and attributed-string rebuilds stay quiet.
        guard committed != committedText || tentative != tentativeText else { return }

        // Compose before publishing so any view invalidated by the @Published
        // text fields already sees a consistent display cache.
        let composed = StreamingRefinementCoordinator.composeDisplay(
            committed: committed,
            tentative: tentative
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        displayText = composed
        displayTail = Self.makeDisplayTail(from: composed)

        committedText = committed
        tentativeText = tentative
    }

    func beginEnhancing() {
        guard phase == .streaming else { return }
        phase = .enhancing
    }

    func end() {
        clearDisplayCaches()
        phase = .inactive
        committedText = ""
        tentativeText = ""
    }

    private func clearDisplayCaches() {
        displayText = ""
        displayTail = ""
    }

    /// Keep the newest characters that fit the three-line viewport, preferring a
    /// word boundary near the cut so the first visible glyph isn't a mid-word slice.
    static func makeDisplayTail(
        from text: String,
        limit: Int = displayTailCharacterLimit
    ) -> String {
        guard text.count > limit else { return text }

        let start = text.index(text.endIndex, offsetBy: -limit)
        var tail = String(text[start...])

        if let whitespace = tail.firstIndex(where: \.isWhitespace) {
            let leadingPartial = tail.distance(from: tail.startIndex, to: whitespace)
            // Only skip a short orphaned prefix; a long run without spaces (URLs,
            // CJK) should not collapse the whole tail.
            if leadingPartial > 0, leadingPartial < 48 {
                let after = tail.index(after: whitespace)
                if after < tail.endIndex {
                    tail = String(tail[after...])
                }
            }
        }

        return tail
    }
}
