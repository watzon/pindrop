//
//  TranscriptionRecord.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftData

@Model
final class TranscriptionRecord {

    @Attribute(.unique) var id: UUID
    var text: String
    var originalText: String?
    var timestamp: Date
    var duration: TimeInterval
    var modelUsed: String
    var enhancedWith: String?
    @Transient var wasEnhanced: Bool = false

    init(
        id: UUID = UUID(),
        text: String,
        originalText: String? = nil,
        timestamp: Date = Date(),
        duration: TimeInterval,
        modelUsed: String,
        enhancedWith: String? = nil
    ) {
        self.id = id
        self.text = text
        self.originalText = originalText
        self.timestamp = timestamp
        self.duration = duration
        self.modelUsed = modelUsed
        self.enhancedWith = enhancedWith
        self.wasEnhanced = originalText != nil && originalText != text
    }
}
