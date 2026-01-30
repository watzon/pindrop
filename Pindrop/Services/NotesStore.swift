//
//  NotesStore.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class NotesStore {
    
    enum NotesStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case searchFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save note: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch notes: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete note: \(message)"
            case .searchFailed(let message):
                return "Failed to search notes: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func create(
        title: String,
        content: String,
        tags: [String] = [],
        sourceTranscriptionID: UUID? = nil
    ) throws {
        let note = Note(
            title: title,
            content: content,
            tags: tags,
            sourceTranscriptionID: sourceTranscriptionID
        )
        
        modelContext.insert(note)
        
        do {
            try modelContext.save()
        } catch {
            throw NotesStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func fetchAll() throws -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw NotesStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func fetch(limit: Int) throws -> [Note] {
        var descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw NotesStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func update(_ note: Note) throws {
        note.updatedAt = Date()
        
        do {
            try modelContext.save()
        } catch {
            throw NotesStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func delete(_ note: Note) throws {
        modelContext.delete(note)
        
        do {
            try modelContext.save()
        } catch {
            throw NotesStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            try modelContext.delete(model: Note.self)
            try modelContext.save()
        } catch {
            throw NotesStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func search(query: String) throws -> [Note] {
        let predicate = #Predicate<Note> { note in
            note.title.localizedStandardContains(query) ||
            note.content.localizedStandardContains(query)
        }
        
        let descriptor = FetchDescriptor<Note>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw NotesStoreError.searchFailed(error.localizedDescription)
        }
    }
    
    func togglePin(_ note: Note) throws {
        note.isPinned.toggle()
        note.updatedAt = Date()
        
        do {
            try modelContext.save()
        } catch {
            throw NotesStoreError.saveFailed(error.localizedDescription)
        }
    }
}
