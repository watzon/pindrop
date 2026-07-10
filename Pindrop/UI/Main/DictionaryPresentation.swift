//
//  DictionaryPresentation.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Pure helpers for Dictionary page presentation (U6). No SwiftUI / SwiftData side effects.
//

import Foundation

// MARK: - Vocabulary chip ordering

enum DictionaryVocabularyOrdering {
    /// Sort by usageCount descending, then alphabetically (case-insensitive).
    /// Pure tuple form for unit tests — does **not** uniquing; duplicates are preserved.
    static func sortedChips(
        words: [(word: String, usageCount: Int)]
    ) -> [(word: String, usageCount: Int)] {
        words.sorted(by: compareChip)
    }

    /// Sort vocabulary models for chip display without collapsing case/exact duplicates.
    /// Building a `Dictionary(uniqueKeysWithValues:)` keyed by `word.lowercased()` traps
    /// when import or store state contains case-variant or exact duplicates.
    static func sortedModels(_ words: [VocabularyWord]) -> [VocabularyWord] {
        words.sorted { lhs, rhs in
            compareChip(
                (word: lhs.word, usageCount: lhs.usageCount),
                (word: rhs.word, usageCount: rhs.usageCount)
            )
        }
    }

    private static func compareChip(
        _ lhs: (word: String, usageCount: Int),
        _ rhs: (word: String, usageCount: Int)
    ) -> Bool {
        if lhs.usageCount != rhs.usageCount {
            return lhs.usageCount > rhs.usageCount
        }
        return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
    }
}

// MARK: - Match mode labels

enum DictionaryMatchModeLabel {
    static func label(for mode: ReplacementMatchMode, locale: Locale) -> String {
        switch mode {
        case .caseInsensitive:
            return localized("case-insensitive", locale: locale)
        case .exact:
            return localized("exact", locale: locale)
        case .command:
            return localized("command", locale: locale)
        }
    }
}

// MARK: - Command-token display

/// Maps stored command-mode replacement values to readable palette glyphs for the UI.
enum DictionaryCommandTokenDisplay {
    /// Readable form for list cells, e.g. "⏎⏎" for newParagraph, "⏎" for newLine, "⇥" for tab.
    static func displayString(for storedValue: String) -> String {
        let resolved = ReplacementCommandPalette.resolve(storedValue)
        switch resolved {
        case "\n\n":
            return "⏎⏎"
        case "\n":
            return "⏎"
        case "\t":
            return "⇥"
        default:
            // If the stored value is a known palette token that resolve left as-is
            // (custom escape hatch), still map common token names.
            let normalized = storedValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            switch normalized {
            case "newparagraph", "new paragraph":
                return "⏎⏎"
            case "newline", "new line":
                return "⏎"
            case "tab":
                return "⇥"
            default:
                // Show a printable escape for embedded control sequences.
                if resolved.contains(where: { $0.isNewline || $0 == "\t" }) {
                    return resolved
                        .replacingOccurrences(of: "\n", with: "⏎")
                        .replacingOccurrences(of: "\t", with: "⇥")
                }
                return storedValue
            }
        }
    }

    /// Pattern column for a replacement row (joined originals).
    static func patternDisplay(originals: [String]) -> String {
        originals.joined(separator: ", ")
    }

    /// Replacement column — command mode uses glyph form; others use raw text.
    static func replacementDisplay(
        replacement: String,
        matchMode: ReplacementMatchMode
    ) -> String {
        if matchMode == .command {
            return displayString(for: replacement)
        }
        return replacement
    }
}
