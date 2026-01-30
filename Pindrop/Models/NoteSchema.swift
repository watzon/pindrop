//
//  NoteSchema.swift
//  Pindrop
//
//  Created on 2026-01-29.
//  Schema versioning for Note to support future migrations
//

import Foundation
import SwiftData

enum NoteSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Note.self]
    }
    
    @Model
    final class Note {
        @Attribute(.unique) var id: UUID
        var title: String
        var content: String
        var tags: [String]
        var sourceTranscriptionID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        
        init(
            id: UUID = UUID(),
            title: String,
            content: String,
            tags: [String] = [],
            sourceTranscriptionID: UUID? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isPinned: Bool = false
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.tags = tags
            self.sourceTranscriptionID = sourceTranscriptionID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
        }
    }
}

// V1 Schema Version
enum NoteSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Note.self]
    }
    
    @Model
    final class Note {
        @Attribute(.unique) var id: UUID
        var title: String
        var content: String
        var tags: [String]
        var sourceTranscriptionID: UUID?
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        
        init(
            id: UUID = UUID(),
            title: String,
            content: String,
            tags: [String] = [],
            sourceTranscriptionID: UUID? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            isPinned: Bool = false
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.tags = tags
            self.sourceTranscriptionID = sourceTranscriptionID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
        }
    }
}
