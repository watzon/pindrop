//
// PromptPreset.swift
// Pindrop
//
// Created on 2026-02-02.
//

import Foundation
import SwiftData

@Model
final class PromptPreset {

    @Attribute(.unique) var id: UUID
    var name: String
    var prompt: String
    var isBuiltIn: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var builtInIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        builtInIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.builtInIdentifier = builtInIdentifier
    }
}
