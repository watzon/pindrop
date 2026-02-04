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

    /// Definition of a preset including its identifier, display name, and prompt template.
    struct PresetDefinition: Identifiable, Equatable {
        let identifier: String
        let name: String
        let prompt: String

        var id: String { identifier }
    }

    /// All built-in presets in display order.
    static let all: [PresetDefinition] = [
        cleanTranscript,
        meetingNotes,
        emailDraft,
        socialMedia,
        bulletSummary,
        technical
    ]

    /// The default preset used when no user preference is set.
    static let defaultPreset: PresetDefinition = cleanTranscript

    // MARK: - Preset Definitions

    /// Clean Transcript - General purpose cleanup with number conversion and filler removal.
    static let cleanTranscript = PresetDefinition(
        identifier: "clean",
        name: "Clean Transcript",
        prompt: """
        You are a transcription cleanup assistant. Process the dictated text:
        1. Fix spelling, grammar, and punctuation errors
        2. Convert number words to digits (twenty-five → 25, ten percent → 10%)
        3. Replace spoken punctuation with symbols (period → ., comma → ,, question mark → ?)
        4. Remove filler words (um, uh, like, you know) unless they add meaning
        5. Fix capitalization (sentence starts, proper nouns)
        Preserve exact meaning and word order. Do not paraphrase or reorder.
        Return only the cleaned text.
        ${transcription}
        """
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
        """
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
        """
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
        """
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
        """
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
        """
    )
}
