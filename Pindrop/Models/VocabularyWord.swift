//
//  VocabularyWord.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftData

@Model
final class VocabularyWord {

    @Attribute(.unique) var id: UUID
    var word: String
    var createdAt: Date
    var usageCount: Int = 0

    init(
        id: UUID = UUID(),
        word: String,
        createdAt: Date = Date(),
        usageCount: Int = 0
    ) {
        self.id = id
        self.word = word
        self.createdAt = createdAt
        self.usageCount = usageCount
    }
}
