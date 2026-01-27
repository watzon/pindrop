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

    init(
        id: UUID = UUID(),
        originals: [String],
        replacement: String,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.originals = originals
        self.replacement = replacement
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
