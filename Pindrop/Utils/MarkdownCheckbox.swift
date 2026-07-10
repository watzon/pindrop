//
//  MarkdownCheckbox.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

/// Pure helpers for GitHub-style markdown task list items (`- [ ]` / `- [x]`).
enum MarkdownCheckbox {
    struct Match: Equatable, Sendable {
        /// UTF-16 offset of the line start.
        let lineStart: Int
        /// UTF-16 range of the bracket marker including brackets, e.g. `[ ]` or `[x]`.
        let markerRange: NSRange
        /// UTF-16 range of the item text after the marker and following whitespace.
        let contentRange: NSRange
        /// UTF-16 range of the full line (excluding trailing newline).
        let lineRange: NSRange
        let isChecked: Bool
    }

    /// Pattern: optional indent, `-`, spaces, `[ ]` or `[x]`/`[X]`, then rest of line.
    private static let linePattern = #"^([ \t]*)-[ \t]+\[([ xX])\]([ \t]*)(.*)$"#

    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: linePattern,
        options: .anchorsMatchLines
    )

    static func matches(in text: String) -> [Match] {
        guard let regex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { result in
            guard result.numberOfRanges >= 5 else { return nil }
            let stateRange = result.range(at: 2)
            guard stateRange.location != NSNotFound else { return nil }
            let state = nsText.substring(with: stateRange)
            let isChecked = state.lowercased() == "x"

            let full = result.range(at: 0)
            // Marker is `[` + state + `]` immediately after the match of group 2's surroundings.
            // Reconstruct marker range from the full match text.
            let lineText = nsText.substring(with: full)
            guard let marker = firstMarkerRange(in: lineText) else { return nil }
            let markerRange = NSRange(
                location: full.location + marker.location,
                length: marker.length
            )

            let trailingSpaceRange = result.range(at: 3)
            let contentGroup = result.range(at: 4)
            let contentLocation: Int
            let contentLength: Int
            if contentGroup.location != NSNotFound {
                contentLocation = contentGroup.location
                contentLength = contentGroup.length
            } else {
                contentLocation = markerRange.location + markerRange.length
                contentLength = 0
            }
            // Include trailing space group end so content starts after marker spacing.
            _ = trailingSpaceRange

            return Match(
                lineStart: full.location,
                markerRange: markerRange,
                contentRange: NSRange(location: contentLocation, length: contentLength),
                lineRange: full,
                isChecked: isChecked
            )
        }
    }

    /// Toggles the checkbox whose marker contains `utf16Offset`.
    /// Returns `nil` when the offset is not on a checkbox marker (so normal editing still works).
    static func toggle(in text: String, utf16Offset: Int) -> String? {
        let hits = matches(in: text)
        guard let match = hits.first(where: { hit in
            NSLocationInRange(utf16Offset, hit.markerRange)
        }) else {
            return nil
        }
        return applyingToggle(to: text, match: match)
    }

    /// Toggles the checkbox on the zero-based line index, if that line is a task item.
    static func toggleLine(in text: String, lineIndex: Int) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineIndex >= 0, lineIndex < lines.count else { return nil }

        var utf16Offset = 0
        for (index, line) in lines.enumerated() {
            if index == lineIndex {
                let lineMatches = matches(in: String(line))
                guard let first = lineMatches.first else { return nil }
                // Rebuild with absolute offset for the single-line match.
                let absolute = Match(
                    lineStart: utf16Offset + first.lineStart,
                    markerRange: NSRange(
                        location: utf16Offset + first.markerRange.location,
                        length: first.markerRange.length
                    ),
                    contentRange: NSRange(
                        location: utf16Offset + first.contentRange.location,
                        length: first.contentRange.length
                    ),
                    lineRange: NSRange(
                        location: utf16Offset + first.lineRange.location,
                        length: first.lineRange.length
                    ),
                    isChecked: first.isChecked
                )
                return applyingToggle(to: text, match: absolute)
            }
            utf16Offset += (line as NSString).length + 1 // + newline
        }
        return nil
    }

    static func applyingToggle(to text: String, match: Match) -> String {
        let nsText = text as NSString
        let replacement = match.isChecked ? "[ ]" : "[x]"
        return nsText.replacingCharacters(in: match.markerRange, with: replacement)
    }

    private static func firstMarkerRange(in line: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"\[[ xX]\]"#) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, range: range)?.range
    }
}
