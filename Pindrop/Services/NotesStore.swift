//
//  NotesStore.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation
import SwiftData
import os.log

@MainActor
@Observable
final class NotesStore {
    
    enum NotesStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case searchFailed(String)
        case metadataGenerationFailed(String)
        
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
            case .metadataGenerationFailed(let message):
                return "Failed to generate metadata: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    private let aiEnhancementService: AIEnhancementService?
    private let settingsStore: SettingsStore?
    
    init(
        modelContext: ModelContext,
        aiEnhancementService: AIEnhancementService? = nil,
        settingsStore: SettingsStore? = nil
    ) {
        self.modelContext = modelContext
        self.aiEnhancementService = aiEnhancementService
        self.settingsStore = settingsStore
    }
    
    func create(
        title: String? = nil,
        content: String,
        tags: [String]? = nil,
        sourceTranscriptionID: UUID? = nil,
        generateMetadata: Bool = false
    ) async throws {
        var finalTitle = title
        var finalTags = tags
        
        // Generate metadata if requested and AI enhancement is enabled
        if generateMetadata,
           let settings = settingsStore,
           settings.aiEnhancementEnabled,
           let aiService = aiEnhancementService {
            if let endpoint = settings.apiEndpoint,
               let apiKey = settings.apiKey {
                do {
                    let metadata = try await aiService.generateNoteMetadata(
                        content: content,
                        apiEndpoint: endpoint,
                        apiKey: apiKey,
                        model: settings.aiModel
                    )
                    
                    // Use generated title if no explicit title provided
                    if finalTitle == nil {
                        finalTitle = metadata.title
                    }
                    
                    // Use generated tags if no explicit tags provided
                    if finalTags == nil {
                        finalTags = metadata.tags
                    }
                } catch {
                    Log.aiEnhancement.warning("Failed to generate note metadata: \(error.localizedDescription)")
                    // Fall back to default behavior on AI failure
                }
            }
        }
        
        // Fall back to first 30 chars of content if no title
        if finalTitle == nil || finalTitle?.isEmpty == true {
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty {
                finalTitle = "Untitled Note"
            } else if trimmedContent.count <= 30 {
                finalTitle = trimmedContent
            } else {
                let index = trimmedContent.index(trimmedContent.startIndex, offsetBy: 30)
                finalTitle = String(trimmedContent[..<index]) + "..."
            }
        }
        
        // Use empty array if no tags
        if finalTags == nil {
            finalTags = []
        }
        
        let note = Note(
            title: finalTitle!,
            content: content,
            tags: finalTags!,
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
