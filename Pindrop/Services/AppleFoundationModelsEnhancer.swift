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

// MARK: - Enhancer

@available(macOS 26, *)
@MainActor
final class AppleFoundationModelsEnhancer {

    private var enhancementSession: LanguageModelSession?
    private var lastEnhancementPrompt: String?

    // MARK: - Text Enhancement

    func enhance(text: String, systemPrompt: String) async throws -> String {
        try checkAvailability()

        if enhancementSession == nil || lastEnhancementPrompt != systemPrompt {
            enhancementSession = LanguageModelSession(instructions: systemPrompt)
            lastEnhancementPrompt = systemPrompt
        }

        guard let session = enhancementSession else {
            throw AIEnhancementService.EnhancementError.apiError("Failed to create Apple Intelligence session.")
        }

        return try await runWithErrorMapping {
            let response = try await session.respond(to: text)
            return response.content
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
            // Reset session and retry once with fresh context
            enhancementSession = nil
            lastEnhancementPrompt = nil
            do {
                return try await body()
            } catch {
                throw AIEnhancementService.EnhancementError.apiError(
                    "Content too long for Apple Intelligence: \(error.localizedDescription)"
                )
            }
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
