//
//  String+WordCount.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

extension String {
    /// Number of whitespace/newline-delimited tokens, ignoring empty segments.
    ///
    /// Single linear scan — no intermediate `split`/`filter` arrays.
    var wordCount: Int {
        var count = 0
        var inWord = false
        for character in self {
            if character.isWhitespace || character.isNewline {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }
}
