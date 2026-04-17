//
//  AppleFoundationModelsEnhancer.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable output types

@available(macOS 26, *)
@Generable
struct AppleTranscriptionMetadata {
    @Guide(description: "Concise descriptive title in 4-8 words that summarizes the transcription. Empty string if title is not needed.")
    var title: String

    @Guide(description: "2-4 sentence summary that captures the main discussion, decisions, and outcomes of the transcription.")
    var summary: String
}

@available(macOS 26, *)
@Generable
struct AppleNoteMetadata {
    @Guide(description: "Concise title summarizing the note content in 5-10 words.")
    var title: String

    @Guide(description: "3-5 relevant lowercase tags for categorizing this note content. Each tag should be a single word or short two-word phrase.")
    var tags: [String]
}

// MARK: - Live streaming edit-list schema (L2)
//
// `@Generable` requires FoundationModels, so these types live behind the same guard as
// the rest of the file. The coordinator consumes a plain `TranscriptEdit` (declared in
// `TranscriptEdit.swift`) so it doesn't need to be gated. `refineAsEdits` converts.

@available(macOS 26, *)
@Generable
struct AppleTranscriptEditList {
    @Guide(description: """
        Ordered list of small find-and-replace edits to clean up the transcript. Each edit \
        applies to the result of the previous ones. Prefer many small edits over one big \
        edit. Return an empty list when the transcript is already clean.
        """)
    var edits: [AppleTranscriptEdit]
}

@available(macOS 26, *)
@Generable
struct AppleTranscriptEdit {
    @Guide(description: """
        Exact substring from the transcript to replace. MUST match the input verbatim, \
        including spaces and punctuation. If the target word or phrase could appear in \
        multiple places in the transcript, include 2-3 surrounding words (or a unique \
        preceding/following word) so that this `find` string only matches the intended \
        occurrence.
        """)
    var find: String

    @Guide(description: """
        Replacement for `find`. May be an empty string to delete. Keep replacements \
        minimal: fix capitalization, insert punctuation, remove filler words, merge \
        split words (e.g. `correct ly` -> `correctly`). Do NOT restructure sentences \
        or paraphrase. Do NOT add content that the speaker did not say.
        """)
    var replacement: String
}

// MARK: - Enhancer

@available(macOS 26, *)
@MainActor
final class AppleFoundationModelsEnhancer {

    // MARK: - Text Enhancement

    func enhance(text: String, systemPrompt: String) async throws -> String {
        try checkAvailability()

        // Strip any `${transcription}` placeholder from the instructions. The cloud
        // provider path normalizes this via `normalizeTranscriptionInstructions`, but
        // the Apple path bypasses that — if we don't strip here the model sees
        // `${transcription}` as literal text in its instructions, which confuses it.
        let normalizedInstructions = systemPrompt
            .replacingOccurrences(of: "${transcription}", with: "")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fresh session per call. Caching the session across calls (as earlier
        // versions did) caused Foundation Models to treat each refinement as a
        // continuation of a multi-turn conversation and echo the input verbatim
        // instead of applying the cleanup instructions. `generateTranscriptionMetadata`
        // below always uses a fresh session and worked correctly for that reason.
        let session = LanguageModelSession(instructions: normalizedInstructions)

        return try await runWithErrorMapping {
            let response = try await session.respond(to: text)
            return response.content
        }
    }

    // MARK: - Live Streaming Refinement (edit list)

    /// Returns a list of find/replace edits the coordinator can apply to the transcript
    /// to clean it up. Structured output via `@Generable` constrains the model to
    /// grounded edits — it cannot hallucinate unspoken trailing content because any
    /// `find` that isn't actually present in the transcript would be skipped by the
    /// applier. Fresh session per call, same contract as `enhance(...)`.
    func refineAsEdits(
        transcript: String,
        systemPrompt: String
    ) async throws -> [TranscriptEdit] {
        try checkAvailability()

        let normalizedInstructions = systemPrompt
            .replacingOccurrences(of: "${transcription}", with: "")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let session = LanguageModelSession(instructions: normalizedInstructions)

        let result = try await runWithErrorMapping {
            let response = try await session.respond(
                to: transcript,
                generating: AppleTranscriptEditList.self
            )
            return response.content
        }
        return result.edits.map {
            TranscriptEdit(find: $0.find, replacement: $0.replacement)
        }
    }

    // MARK: - Transcription Metadata

    func generateTranscriptionMetadata(
        transcription: String,
        includeTitle: Bool
    ) async throws -> (title: String?, summary: String) {
        try checkAvailability()

        let instructions = """
        You are a transcript analysis assistant. Analyze the provided transcription and generate structured metadata.
        \(includeTitle ? "Provide a concise title that describes the main topic." : "Leave the title empty.")
        Provide a 2-4 sentence summary capturing the main discussion, decisions, and outcomes.
        Only reference details that are explicitly present in the transcription.
        """

        let session = LanguageModelSession(instructions: instructions)

        let metadata = try await runWithErrorMapping {
            let response = try await session.respond(
                to: transcription,
                generating: AppleTranscriptionMetadata.self
            )
            return response.content
        }

        let cleanTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = metadata.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSummary.isEmpty else {
            throw AIEnhancementService.EnhancementError.invalidResponse
        }

        return (
            (includeTitle && !cleanTitle.isEmpty) ? cleanTitle : nil,
            cleanSummary
        )
    }

    // MARK: - Note Metadata

    func generateNoteMetadata(
        content: String,
        existingTags: [String]
    ) async throws -> (title: String, tags: [String]) {
        try checkAvailability()

        var instructions = """
        You are a note organization assistant. Analyze the note content and generate a concise title and relevant tags.
        - Title: 5-10 words that summarize the main topic
        - Tags: 3-5 lowercase keywords for categorization (single words or short phrases)
        """

        if !existingTags.isEmpty {
            let tagList = existingTags.prefix(30).joined(separator: ", ")
            instructions += "\nPrefer these existing tags when relevant: \(tagList)"
        }

        let session = LanguageModelSession(instructions: instructions)

        let metadata = try await runWithErrorMapping {
            let response = try await session.respond(
                to: content,
                generating: AppleNoteMetadata.self
            )
            return response.content
        }

        let cleanTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTags = metadata.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return (cleanTitle.isEmpty ? "Untitled Note" : cleanTitle, cleanTags)
    }

    // MARK: - Private helpers

    private func checkAvailability() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw AIEnhancementService.EnhancementError.apiError(
                "Apple Intelligence is not available: \(reason)"
            )
        }
    }

    private func runWithErrorMapping<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            throw AIEnhancementService.EnhancementError.apiError(
                "Apple Intelligence content policy prevented this enhancement."
            )
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Fresh sessions now, so nothing to reset — just surface the error.
            throw AIEnhancementService.EnhancementError.apiError(
                "Content too long for Apple Intelligence."
            )
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw AIEnhancementService.EnhancementError.apiError(
                "Apple Intelligence does not support the current language or locale."
            )
        } catch let error as AIEnhancementService.EnhancementError {
            throw error
        } catch {
            throw AIEnhancementService.EnhancementError.apiError(error.localizedDescription)
        }
    }
}

#endif // canImport(FoundationModels)
