//
//  String+WordCount.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

extension String {
    /// Number of whitespace/newline-delimited tokens, ignoring empty segments.
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count
    }
}
