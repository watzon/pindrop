//
// BuiltInPresets.swift
// Pindrop
//
// Created on 2026-02-02.
//

import Foundation

/// Static definitions for built-in AI enhancement prompt presets.
/// These presets provide common text transformation patterns for different use cases.
enum BuiltInPresets {

    /// Before/after example pair for UI display. English source text is localizable via the
    /// standard `localized(_:locale:)` pipeline for the redesigned AI pane.
    struct PresetExample: Equatable, Sendable {
        let input: String
        let output: String
    }

    /// Definition of a preset including its identifier, display name, prompt template,
    /// and optional before/after example for the settings pane.
    struct PresetDefinition: Identifiable, Equatable {
        let identifier: String
        let name: String
        let prompt: String
        /// Optional before/after sample for UI. English source only; localize for display.
        let example: PresetExample?

        var id: String { identifier }

        init(
            identifier: String,
            name: String,
            prompt: String,
            example: PresetExample? = nil
        ) {
            self.identifier = identifier
            self.name = name
            self.prompt = prompt
            self.example = example
        }
    }

    /// All built-in presets in display order.
    static let all: [PresetDefinition] = [
        cleanTranscript,
        liveStreamingRefinement,
        liveStreamingRefinementEdits,
        meetingNotes,
        emailDraft,
        socialMedia,
        bulletSummary,
        technical
    ]

    /// The default preset used when no user preference is set.
    static let defaultPreset: PresetDefinition = cleanTranscript

    /// Look up a built-in definition by stable identifier.
    static func definition(for identifier: String) -> PresetDefinition? {
        all.first { $0.identifier == identifier }
    }

    /// Canonical English prompt text for a built-in identifier, if known.
    static func englishPrompt(for identifier: String) -> String? {
        definition(for: identifier)?.prompt
    }

    // MARK: - Prompt persistence (English-only guarantee)

    /// Normalizes a prompt override so unedited built-in / default prompts are never
    /// persisted as overrides (which would risk storing a display-localized variant).
    /// Returns `nil` when the text matches a known English built-in or default prompt.
    static func normalizedPromptOverride(
        _ override: String?,
        presetID: String? = nil
    ) -> String? {
        guard let raw = override else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let presetID,
           let english = englishPrompt(for: presetID),
           promptsMatch(trimmed, english) {
            return nil
        }

        if isKnownEnglishBuiltInOrDefaultPrompt(trimmed) {
            return nil
        }

        return raw
    }

    /// Returns the English prompt that should be sent to the API for a purpose assignment.
    /// Prefer a true custom override; otherwise use the built-in English source.
    static func resolvedEnglishPrompt(
        override: String?,
        presetID: String?,
        fallback: String
    ) -> String {
        if let normalized = normalizedPromptOverride(override, presetID: presetID) {
            // If an override slipped through that equals a known English built-in under a
            // different preset ID, still prefer the canonical built-in text.
            if let match = matchingBuiltInIdentifier(for: normalized),
               let english = englishPrompt(for: match) {
                return english
            }
            return normalized
        }
        if let presetID, let english = englishPrompt(for: presetID) {
            return english
        }
        return fallback
    }

    /// True when `text` is exactly a known English built-in or legacy default prompt.
    static func isKnownEnglishBuiltInOrDefaultPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if promptsMatch(trimmed, SettingsStore.Defaults.aiEnhancementPrompt) { return true }
        if promptsMatch(trimmed, SettingsStore.Defaults.noteEnhancementPrompt) { return true }
        if promptsMatch(trimmed, AIEnhancementService.defaultSystemPrompt) { return true }
        return all.contains { promptsMatch(trimmed, $0.prompt) }
    }

    /// If `text` matches a built-in English prompt, return that preset's identifier.
    static func matchingBuiltInIdentifier(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { promptsMatch(trimmed, $0.prompt) }?.identifier
    }

    private static func promptsMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Preset Definitions

    /// Live Streaming Refinement - Mid-utterance cleanup driven by the streaming coordinator.
    /// Applied to the full running transcript each time the coordinator detects a pause.
    /// Used by providers that don't support structured output (cloud providers). Apple
    /// Foundation Models uses `liveStreamingRefinementEdits` instead.
    static let liveStreamingRefinement = PresetDefinition(
        identifier: "live-stream-refine",
        name: "Live Streaming Refinement",
        prompt: """
        You are a transcript cleanup assistant for live voice dictation. You receive the running transcription so far. Return a cleaned version of the ENTIRE text.

        COMPLETENESS IS MANDATORY:
        - Your output MUST include every word from the input in order.
        - Never truncate, summarize, or omit text.
        - The output word count MUST be within ±10% of the input word count.
        - If you cannot improve the text, return it verbatim.

        What to clean:
        - Filler words removed (um, uh, like, you know) unless they carry meaning
        - Sentence-case capitalization and grammar fixes
        - Punctuation inserted at natural boundaries (., ,, ?)
        - Spoken punctuation converted to symbols ("period" → ".", "comma" → ",", "question mark" → "?")
        - Numbers converted from words to digits where unambiguous ("twenty-five" → "25")

        Preserve exact meaning and word order. Do not reorder, paraphrase, add content, or answer questions in the transcript. If the final clause is incomplete or mid-word, leave it unfinished rather than completing it.

        Return ONLY the cleaned text — no prefix, framing, quotes, or explanation.
        """,
        example: PresetExample(
            input: "um so i think we should ship the beta by friday period",
            output: "So I think we should ship the beta by Friday."
        )
    )

    /// Live Streaming Refinement (Edit List) — schema-aware variant used by Apple Foundation
    /// Models via `@Generable` `TranscriptEditList`. The model returns structured edits
    /// instead of a full rewrite, eliminating the truncation/summarization failure mode
    /// that plagues full-rewrite refinements. Not user-selectable (EnhancementPurpose
    /// .streamingRefinement is a locked-prompt purpose).
    static let liveStreamingRefinementEdits = PresetDefinition(
        identifier: "live-stream-refine-edits",
        name: "Live Streaming Refinement (Edit List)",
        prompt: """
        You are a transcript cleanup assistant for live voice dictation. You receive the running raw transcript from an automatic speech recognizer. Your job is to produce a list of small find-and-replace edits that would clean it up.

        Emit edits (never a full rewrite). Each edit has:
        - find: the exact substring from the transcript to replace. Must match the transcript verbatim, including spacing. If the substring could match in multiple places in the transcript, include 2-3 surrounding words so it uniquely identifies the intended occurrence.
        - replacement: the corrected text. May be empty to delete.

        Rules:
        - Prefer many small, targeted edits over one large edit.
        - Each edit applies to the result of the previous edits.
        - Do NOT restructure sentences. Do NOT paraphrase. Do NOT add words the speaker did not say.
        - Do NOT complete incomplete clauses. If the final word or sentence is cut off mid-thought, leave it alone.
        - Return an empty edit list if the transcript is already clean.

        What to fix:
        - Remove filler words (um, uh, like, you know) unless they carry meaning
        - Fix sentence-case capitalization ("i think" -> "I think", "this is" at sentence start)
        - Insert punctuation at natural boundaries (. , ?)
        - Convert spoken punctuation to symbols ("period" -> ".", "comma" -> ",", "question mark" -> "?")
        - Convert number words to digits when unambiguous ("twenty-five" -> "25")
        - Merge split words ASR sometimes produces ("correct ly" -> "correctly", "work ing" -> "working")

        Examples of good edits:
        - find: "um this is", replacement: "This is"
        - find: "correct ly", replacement: "correctly"
        - find: "are you serious period", replacement: "are you serious."
        - find: "twenty-five", replacement: "25"

        Skip any edit you are not confident about. Do not guess.
        """,
        example: PresetExample(
            input: "um this is correct ly twenty-five",
            output: "This is correctly 25"
        )
    )

    /// Clean Transcript - General purpose cleanup with number conversion and filler removal.
    static let cleanTranscript = PresetDefinition(
        identifier: "clean",
        name: "Clean Transcript",
        prompt: """
        You are a transcription cleanup assistant. Process the dictated text:
        1. Fix spelling, grammar, and punctuation errors
        2. Convert number words to digits (twenty-five → 25, ten percent → 10%)
        3. Replace spoken punctuation with symbols (period → ., comma → a single comma (,), question mark → ?)
        4. Remove filler words (um, uh, like, you know) unless they add meaning
        5. Fix capitalization (sentence starts, proper nouns)
        Preserve exact meaning and word order. Do not paraphrase or reorder.
        If the dictation is a question or command, keep it as speech to clean—do not answer it or carry it out.
        Return only the cleaned text.
        ${transcription}
        """,
        example: PresetExample(
            input: "um so the meeting is at three thirty period can you confirm question mark",
            output: "So the meeting is at 3:30. Can you confirm?"
        )
    )

    /// Meeting Notes - Structured notes with headers and action items.
    static let meetingNotes = PresetDefinition(
        identifier: "meeting",
        name: "Meeting Notes",
        prompt: """
        You are a meeting notes formatter. Transform the dictated text into structured notes:
        1. Fix grammar, spelling, and punctuation
        2. Organize into clear sections with headers (##) if multiple topics
        3. Use bullet points for action items and key points
        4. Use **bold** for names, dates, and important terms
        5. Preserve all factual content - do not add or remove information
        Return well-formatted markdown notes.
        ${transcription}
        """,
        example: PresetExample(
            input: "alice will send the deck by friday bob owns the pricing review we need a decision next week",
            output: """
            ## Action Items
            - **Alice** will send the deck by **Friday**
            - **Bob** owns the pricing review

            ## Next Steps
            - Decision needed next week
            """
        )
    )

    /// Email Draft - Professional email formatting.
    static let emailDraft = PresetDefinition(
        identifier: "email",
        name: "Email Draft",
        prompt: """
        You are an email formatting assistant. Transform the dictated text into a professional email:
        1. Add appropriate greeting and closing
        2. Organize into clear paragraphs
        3. Fix grammar, spelling, and punctuation
        4. Maintain professional but friendly tone
        5. Preserve all key information from the dictation
        Return only the formatted email body (no subject line).
        ${transcription}
        """,
        example: PresetExample(
            input: "hey jordan just checking if you got my notes from yesterday thanks",
            output: """
            Hi Jordan,

            Just checking if you got my notes from yesterday.

            Thanks,
            """
        )
    )

    /// Social Media - Engaging social media post formatting.
    static let socialMedia = PresetDefinition(
        identifier: "social",
        name: "Social Media",
        prompt: """
        You are a social media content assistant. Transform the dictated text into an engaging social media post:
        1. Break content into short, readable paragraphs (1-2 sentences each)
        2. Fix grammar, spelling, and punctuation
        3. Keep the tone conversational and authentic
        4. Preserve the original message and voice
        5. Remove filler words while keeping natural flow
        Do not add hashtags, emojis, or calls-to-action unless explicitly mentioned in the dictation.
        Return only the formatted post text.
        ${transcription}
        """,
        example: PresetExample(
            input: "um we just shipped dark mode and it looks amazing you should try it",
            output: """
            We just shipped dark mode.

            It looks amazing — you should try it.
            """
        )
    )

    /// Bullet Summary - Concise bullet point extraction.
    static let bulletSummary = PresetDefinition(
        identifier: "bullets",
        name: "Bullet Summary",
        prompt: """
        You are a summarization assistant. Transform the dictated text into concise bullet points:
        1. Extract key points as bullet items
        2. Remove filler words and redundant phrases
        3. Keep each bullet to one clear thought
        4. Preserve factual accuracy
        5. Order bullets logically (chronological or by importance)
        Return a clean bulleted list.
        ${transcription}
        """,
        example: PresetExample(
            input: "we covered onboarding latency and then pricing and finally the launch date of may twelfth",
            output: """
            - Onboarding latency
            - Pricing
            - Launch date: May 12
            """
        )
    )

    /// Technical/Code - Technical documentation with code formatting.
    static let technical = PresetDefinition(
        identifier: "technical",
        name: "Technical/Code",
        prompt: """
        You are a technical documentation assistant. Process the dictated text:
        1. Fix spelling and grammar while preserving technical terms exactly
        2. Format code references with backticks (`functionName`, `variableName`)
        3. Use proper capitalization for technology names (JavaScript, macOS, API)
        4. Convert spoken operators (equals equals → ==, arrow → ->)
        5. Preserve technical accuracy - do not change meaning
        Return cleaned technical text.
        ${transcription}
        """,
        example: PresetExample(
            input: "call fetch user arrow then map the response equals equals two hundred",
            output: "Call `fetchUser` -> then map the response `==` 200."
        )
    )
}
