//
//  VocabularyBiasPrompt.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

/// Builds WhisperKit initial-prompt vocabulary bias strings.
///
/// WhisperKit's decoder accepts a short prompt (tokenized into `promptTokens`) that
/// conditions recognition toward known terms. We cap at ``maxWordCount`` (~40) so the
/// prompt stays small relative to the decoder context window — more words yield
/// diminishing returns and can dilute bias.
enum VocabularyBiasPrompt {
    /// Maximum vocabulary words injected into the WhisperKit prompt.
    static let maxWordCount = 40

    struct Entry: Equatable, Sendable {
        let word: String
        let usageCount: Int
        let createdAt: Date
    }

    /// Selects top-N vocabulary words: highest `usageCount` first, then most recent `createdAt`.
    /// Empty / blank words are dropped. Returns an empty array when there is nothing to bias.
    static func selectWords(from entries: [Entry], limit: Int = maxWordCount) -> [String] {
        guard limit > 0 else { return [] }

        let cleaned = entries
            .map { Entry(word: $0.word.trimmingCharacters(in: .whitespacesAndNewlines), usageCount: $0.usageCount, createdAt: $0.createdAt) }
            .filter { !$0.word.isEmpty }

        guard !cleaned.isEmpty else { return [] }

        // Deduplicate case-insensitively, keeping the highest-priority occurrence.
        var seen = Set<String>()
        let ranked = cleaned.sorted { lhs, rhs in
            if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }
            return lhs.createdAt > rhs.createdAt
        }

        var selected: [String] = []
        selected.reserveCapacity(min(limit, ranked.count))
        for entry in ranked {
            let key = entry.word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            selected.append(entry.word)
            if selected.count >= limit { break }
        }
        return selected
    }

    /// Joins selected words into a Whisper-style initial prompt, or `nil` when empty (no-op).
    static func assemblePrompt(words: [String]) -> String? {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: ", ")
    }

    /// Select + assemble in one step.
    static func prompt(from entries: [Entry], limit: Int = maxWordCount) -> String? {
        assemblePrompt(words: selectWords(from: entries, limit: limit))
    }
}
