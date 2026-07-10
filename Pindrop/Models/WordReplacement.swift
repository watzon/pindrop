//
//  WordReplacement.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftData

@Model
final class WordReplacement {

    @Attribute(.unique) var id: UUID
    var originals: [String]
    var replacement: String
    var createdAt: Date
    var sortOrder: Int
    /// Nil means case-insensitive (historical default).
    var matchModeRawValue: String?
    var usageCount: Int = 0

    init(
        id: UUID = UUID(),
        originals: [String],
        replacement: String,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        matchModeRawValue: String? = nil,
        usageCount: Int = 0
    ) {
        self.id = id
        self.originals = originals
        self.replacement = replacement
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.matchModeRawValue = matchModeRawValue
        self.usageCount = usageCount
    }

    /// Resolved match mode; nil or unknown raw values fall back to case-insensitive.
    var matchMode: ReplacementMatchMode {
        guard let matchModeRawValue,
              let mode = ReplacementMatchMode(rawValue: matchModeRawValue) else {
            return .caseInsensitive
        }
        return mode
    }
}
