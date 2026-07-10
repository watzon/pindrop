//
//  ReplacementMatchMode.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

enum ReplacementMatchMode: String {
    case caseInsensitive
    case exact
    case command
}

/// Resolves stored command-mode replacement values into control sequences.
///
/// Command-mode rules match a spoken phrase (case-insensitive, word-boundary) and
/// substitute a control sequence into the transcript — pure text, no keystroke synthesis.
///
/// Stored `replacement` values may be:
/// - **Palette tokens**: `newParagraph`, `newLine`, `tab` (camelCase), or the spoken
///   phrases `new paragraph` / `new line` / `tab` (case-insensitive, flexible whitespace)
/// - **Literal sequences** already containing the control characters (`\n\n`, `\n`, `\t`)
/// - Any other string is used as-is (escape hatch for custom command text)
enum ReplacementCommandPalette {
    static func resolve(_ storedValue: String) -> String {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return storedValue }

        // Already a literal control sequence — keep as-is.
        if trimmed == "\n\n" || trimmed == "\n" || trimmed == "\t" {
            return trimmed
        }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        switch normalized {
        case "newparagraph", "new paragraph":
            return "\n\n"
        case "newline", "new line":
            return "\n"
        case "tab":
            return "\t"
        default:
            return storedValue
        }
    }
}
