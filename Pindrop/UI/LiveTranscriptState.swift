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
    nonisolated static let displayTailCharacterLimit = 360

    /// Phase stays `@Published` so indicator controllers can subscribe to `$phase`
    /// for shell resize / reveal without observing every text partial.
    @Published private(set) var phase: Phase = .inactive

    /// Content fields are ordinary stored properties. Streaming partials batch
    /// one `objectWillChange` per accepted snapshot so Combine/`@ObservedObject`
    /// consumers are not invalidated twice for a single committed+tentative pair.
    private(set) var committedText = ""
    private(set) var tentativeText = ""

    /// Composed, trimmed display string — authoritative cache of the full live
    /// transcript join. Callers that need the complete text (final output
    /// mirrors, accessibility) read this instead of recomposing.
    private(set) var displayText = ""

    /// Bounded suffix of `displayText` for the three-line floating-indicator
    /// viewport. Styling and layout work only this tail.
    private(set) var displayTail = ""

    var isActive: Bool { phase != .inactive }

    func begin() {
        // Phase assignment publishes once; content fields are non-published.
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

        // Compose before publishing so any view invalidated by objectWillChange
        // already sees a consistent display cache.
        let composed = StreamingRefinementCoordinator.composeDisplay(
            committed: committed,
            tentative: tentative
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = Self.makeDisplayTail(from: composed)

        objectWillChange.send()
        displayText = composed
        displayTail = tail
        committedText = committed
        tentativeText = tentative
    }

    func beginEnhancing() {
        guard phase == .streaming else { return }
        phase = .enhancing
    }

    func end() {
        // Phase assignment publishes once; content fields are non-published.
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
    ///
    /// Walks at most `limit` grapheme clusters from the end — never `String.count`
    /// on the full transcript — so streaming cost stays proportional to the
    /// viewport even for long sessions.
    static func makeDisplayTail(
        from text: String,
        limit: Int = displayTailCharacterLimit
    ) -> String {
        guard let start = text.index(
            text.endIndex,
            offsetBy: -limit,
            limitedBy: text.startIndex
        ), start != text.startIndex else {
            // Shorter than or exactly equal to the limit: return the original
            // string (no copy / no mid-string slice).
            return text
        }

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
