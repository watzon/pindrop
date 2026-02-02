//
// ModelCapabilities.swift
// Pindrop
//
// Created on 2026-02-02.
//

import Foundation

/// Utility for detecting AI model capabilities based on model identifiers.
/// Uses static pattern matching against known model names.
enum ModelCapabilities {

    /// Known vision-capable model patterns.
    /// These patterns are matched against model IDs (case-insensitive).
    private static let visionModelPatterns = [
        "gpt-4o",               // OpenAI GPT-4o (all variants)
        "gpt-4-vision",         // OpenAI GPT-4 Vision
        "gpt-4-turbo",          // OpenAI GPT-4 Turbo (has vision)
        "claude-3",             // Anthropic Claude 3 (all variants)
        "claude-3.5",           // Anthropic Claude 3.5
        "gemini-pro-vision",    // Google Gemini Pro Vision
        "gemini-1.5",           // Google Gemini 1.5 (has vision)
        "gemini-2",             // Google Gemini 2.0
    ]

    /// Determines if a model supports vision/image input capabilities.
    ///
    /// This method performs pattern matching against known vision-capable models.
    /// It handles various naming conventions including:
    /// - Direct model names (e.g., "gpt-4o", "claude-3-opus")
    /// - OpenRouter-prefixed models (e.g., "openai/gpt-4o", "anthropic/claude-3-sonnet")
    /// - Versioned variants (e.g., "gpt-4o-2024-08-06")
    ///
    /// - Parameter modelId: The model identifier string to check
    /// - Returns: `true` if the model is known to support vision, `false` otherwise
    static func supportsVision(modelId: String) -> Bool {
        let normalizedId = modelId.lowercased()

        // Check if any known vision pattern is contained in the model ID
        // This handles both direct matches and OpenRouter-style prefixes
        for pattern in visionModelPatterns {
            if normalizedId.contains(pattern) {
                return true
            }
        }

        // Safe fallback: unknown models are assumed to not support vision
        return false
    }
}
