//
//  ProgrammaticTranscriptFormatter.swift
//  Pindrop
//
//  Created on 2026-07-13.
//
//  Fully local, deterministic post-processing that inserts blank-line paragraph
//  breaks into longer dictation so pasted/persisted text is more readable.
//
//  Design rules:
//    - No network, model, or NLP dependency — pure string heuristics.
//    - Conservative. Short utterances, already-formatted text, and ambiguous
//      boundaries (abbreviations, decimals, initials) are left alone.
//    - Applied at most once on the final transcript, immediately before
//      persistence/output. Idempotent on its own output because text that
//      already contains newlines is preserved.
//

import Foundation

struct ProgrammaticTranscriptFormatter: Sendable {

    /// Minimum sentences required before blank-line breaks are introduced.
    /// Must exceed `sentencesPerParagraph` so a single paragraph group cannot
    /// produce a break; with 2 sentences/paragraph this is 3.
    static let minimumSentenceCount = sentencesPerParagraph + 1

    /// Character floor after trimming; shorter text is left single-line.
    static let minimumCharacterCount = 80

    /// Word floor; avoids pathological breaks on brief replies.
    static let minimumWordCount = 12

    /// Sentences grouped into each paragraph before a blank line.
    static let sentencesPerParagraph = 2

    /// Common title/abbreviation tokens (lowercase, without the trailing period).
    /// Intentionally excludes high false-positive words like `us` / `no` that are often
    /// real sentence endings (`Please contact us. Then…`, `No. Continue…`). Numbered
    /// forms like `No. 5` are handled by the boundary rule requiring a letter after the
    /// period, and dotted initialisms like `U.S.` are protected by the single-letter
    /// initial rule plus letter-after-period protection.
    static let commonAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc",
        "eg", "ie", "inc", "ltd", "co", "corp", "dept", "approx", "est",
        "fig", "vol", "pp", "al", "ed", "ave", "blvd", "rd",
        "gen", "gov", "sgt", "capt", "col", "lt", "mt",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept",
        "oct", "nov", "dec", "uk", "eu",
    ]

    /// Quotes / brackets that may trail a sentence terminator and still belong to that
    /// sentence (`He said "Hello." Then…`, `(Really?). Next…`).
    static let trailingClosers = CharacterSet(charactersIn: "\"'”’)]}")

    init() {}

    /// Format `text` with blank-line paragraph breaks when heuristics agree the
    /// input is long, unformatted prose. Empty input and already-structured text
    /// are returned unchanged (aside from outer whitespace trim on formatted output).
    func format(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Preserve anything the user or another stage already structured.
        if trimmed.contains(where: \.isNewline) {
            return trimmed
        }

        guard trimmed.count >= Self.minimumCharacterCount else { return trimmed }

        let wordCount = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count
        guard wordCount >= Self.minimumWordCount else { return trimmed }

        let sentences = Self.splitSentences(trimmed)
        guard sentences.count >= Self.minimumSentenceCount else { return trimmed }

        var paragraphs: [String] = []
        paragraphs.reserveCapacity((sentences.count + Self.sentencesPerParagraph - 1) / Self.sentencesPerParagraph)

        var index = 0
        while index < sentences.count {
            let end = min(index + Self.sentencesPerParagraph, sentences.count)
            let group = sentences[index..<end].joined(separator: " ")
            paragraphs.append(group)
            index = end
        }

        return paragraphs.joined(separator: "\n\n")
    }

    /// Convenience for the output pipeline: byte-for-byte identity when disabled.
    static func formatIfEnabled(_ text: String, enabled: Bool) -> String {
        guard enabled else { return text }
        return ProgrammaticTranscriptFormatter().format(text)
    }

    // MARK: - Sentence splitting

    /// Split prose into sentences using terminator + whitespace heuristics.
    /// Abbreviations, decimals, ellipses, and initials are not treated as ends.
    static func splitSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let chars = Array(text)
        var sentences: [String] = []
        var current = ""
        var i = 0

        while i < chars.count {
            let character = chars[i]
            current.append(character)

            let isTerminator = character == "." || character == "!" || character == "?"
            if isTerminator {
                let protected = character == "." && isProtectedPeriod(chars, at: i)
                if !protected, isSentenceBoundaryAfter(chars, at: i) {
                    // Consume allowed closers into the completed sentence before we skip
                    // the following whitespace — otherwise `.”` leaves `”` for the next
                    // sentence.
                    var end = i + 1
                    while end < chars.count {
                        guard let scalar = chars[end].unicodeScalars.first,
                              trailingClosers.contains(scalar)
                        else { break }
                        current.append(chars[end])
                        end += 1
                    }

                    let sentence = current.trimmingCharacters(in: .whitespaces)
                    if !sentence.isEmpty {
                        sentences.append(sentence)
                    }
                    current = ""
                    i = end
                    while i < chars.count && chars[i].isWhitespace {
                        i += 1
                    }
                    continue
                }
            }

            i += 1
        }

        let trailing = current.trimmingCharacters(in: .whitespaces)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }
        return sentences
    }

    /// True when the period at `index` is part of an abbreviation, decimal, ellipsis,
    /// initialism, or run-on token (e.g. `e.g.`, `example.com`) and must not split.
    static func isProtectedPeriod(_ chars: [Character], at index: Int) -> Bool {
        guard index < chars.count, chars[index] == "." else { return false }

        // Ellipsis / multi-dot runs.
        if index + 1 < chars.count, chars[index + 1] == "." { return true }
        if index > 0, chars[index - 1] == "." { return true }

        // Decimal numbers: 3.14
        if index > 0, chars[index - 1].isNumber,
           index + 1 < chars.count, chars[index + 1].isNumber
        {
            return true
        }

        // Period immediately followed by alphanumerics (e.g., e.g., i.e., file.txt).
        if index + 1 < chars.count {
            let next = chars[index + 1]
            if next.isLetter || next.isNumber {
                return true
            }
        }

        // Word immediately before the period.
        var start = index
        while start > 0, chars[start - 1].isLetter {
            start -= 1
        }
        if start < index {
            let word = String(chars[start..<index])
            let lowered = word.lowercased()
            if commonAbbreviations.contains(lowered) {
                return true
            }
            // Single-letter initial: "J. K. Rowling"
            if word.count == 1, chars[start].isUppercase {
                return true
            }
        }

        return false
    }

    /// True when the terminator at `index` is followed by optional closers, whitespace,
    /// and either end-of-text or a letter starting the next sentence.
    static func isSentenceBoundaryAfter(_ chars: [Character], at index: Int) -> Bool {
        if index + 1 >= chars.count {
            return true
        }

        var cursor = index + 1
        // Allow trailing quotes / brackets immediately after the terminator.
        while cursor < chars.count {
            guard let scalar = chars[cursor].unicodeScalars.first,
                  trailingClosers.contains(scalar)
            else { break }
            cursor += 1
        }

        if cursor >= chars.count {
            return true
        }

        guard chars[cursor].isWhitespace else {
            return false
        }

        while cursor < chars.count, chars[cursor].isWhitespace {
            cursor += 1
        }

        if cursor >= chars.count {
            return true
        }

        // Conservative: next sentence must begin with a letter.
        // This also keeps `No. 5` from splitting (digit after the period).
        return chars[cursor].isLetter
    }
}
