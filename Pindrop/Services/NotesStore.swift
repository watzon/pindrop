//
//  NotesStore.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import Foundation
import SwiftData
import os.log

extension Notification.Name {
    static let pindropNoteTagsDidChange = Notification.Name("PindropNoteTagsDidChange")
}

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
    /// Background projection worker for tag aggregation (same container, separate context).
    private let tagsWorker: NotesTagsProjectionWorker
    /// Sorted unique tags cache; invalidated on tag-affecting note mutations.
    private var uniqueTagsCache: [String]?
    /// Changes whenever a tag-affecting write invalidates an in-flight projection.
    private var uniqueTagsCacheGeneration: UInt = 0
    /// Nonisolated resource ownership so `deinit` can remove the observer without
    /// touching MainActor-isolated stored properties.
    private let noteTagsChangeObserverRegistration = NotesTagsChangeObserverRegistration()
    
    
    init(
        modelContext: ModelContext,
        aiEnhancementService: AIEnhancementService? = nil,
        settingsStore: SettingsStore? = nil
    ) {
        self.modelContext = modelContext
        self.aiEnhancementService = aiEnhancementService
        self.settingsStore = settingsStore
        self.tagsWorker = NotesTagsProjectionWorker(modelContainer: modelContext.container)
        let token = NotificationCenter.default.addObserver(
            forName: .pindropNoteTagsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateUniqueTagsCache()
            }
        }
        noteTagsChangeObserverRegistration.install(token)
    }

    deinit {
        // Nonisolated fallback: only the resource holder is touched.
        noteTagsChangeObserverRegistration.tearDown()
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
        
        // Generate metadata if requested and a noteMetadata assignment resolves.
        if generateMetadata,
           let settings = settingsStore,
           let aiService = aiEnhancementService,
           let assignment = settings.resolveAssignment(for: .noteMetadata)
        {
            do {
                let existingTags = (try? await getAllUniqueTagsAsync()) ?? []
                let metadata = try await aiService.generateNoteMetadata(
                    content: content,
                    apiEndpoint: assignment.endpoint ?? "",
                    apiKey: assignment.apiKey,
                    model: assignment.modelID,
                    existingTags: existingTags,
                    provider: assignment.kind
                )

                if finalTitle == nil {
                    finalTitle = metadata.title
                }
                if finalTags == nil {
                    finalTags = metadata.tags
                }
            } catch {
                Log.aiEnhancement.warning(
                    "Failed to generate note metadata: \(error.localizedDescription)")
                // Fall back to default behavior on AI failure
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
            invalidateUniqueTagsCache()
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
            invalidateUniqueTagsCache()
        } catch {
            throw NotesStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func delete(_ note: Note) throws {
        modelContext.delete(note)
        
        do {
            try modelContext.save()
            invalidateUniqueTagsCache()
        } catch {
            throw NotesStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            try modelContext.delete(model: Note.self)
            try modelContext.save()
            invalidateUniqueTagsCache()
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
            // Pin state does not affect tags; keep cache.
        } catch {
            throw NotesStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    /// Unique note tags, alphabetically sorted.
    ///
    /// Uses a lightweight tags-only projection (no `updatedAt` sort / full-model
    /// materialization) and an in-memory cache invalidated on tag-affecting writes.
    func getAllUniqueTags() throws -> [String] {
        if let uniqueTagsCache {
            return uniqueTagsCache
        }
        do {
            // A dedicated context avoids reusing registered models whose values
            // predate a background editor save in another context.
            let projectionContext = ModelContext(modelContext.container)
            let tags = try NotesTagsProjection.uniqueTags(from: projectionContext)
            uniqueTagsCache = tags
            return tags
        } catch NotesTagsProjectionError.fetchFailed(let message) {
            throw NotesStoreError.fetchFailed(message)
        }
    }

    /// Async path that projects tags on a background model actor when the cache is cold.
    func getAllUniqueTagsAsync() async throws -> [String] {
        if let uniqueTagsCache {
            return uniqueTagsCache
        }
        let generation = uniqueTagsCacheGeneration
        do {
            let tags = try await tagsWorker.uniqueTags()
            guard generation == uniqueTagsCacheGeneration else {
                // A write landed while the background context was fetching. Do not
                // publish its pre-write projection over the invalidation.
                return try getAllUniqueTags()
            }
            uniqueTagsCache = tags
            return tags
        } catch {
            // Fall back to the lightweight synchronous projection.
            return try getAllUniqueTags()
        }
    }

    private func invalidateUniqueTagsCache() {
        uniqueTagsCacheGeneration &+= 1
        uniqueTagsCache = nil
    }
}

// MARK: - Tags change observer (nonisolated for deinit)

/// Owns the NotificationCenter observer token so teardown can run from
/// nonisolated `deinit` without reading MainActor-isolated stored properties
/// on `NotesStore`.
private final class NotesTagsChangeObserverRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    /// Installs a new observer token, removing any previous one.
    func install(_ token: NSObjectProtocol) {
        lock.lock()
        let previous = self.token
        self.token = token
        lock.unlock()
        if let previous {
            NotificationCenter.default.removeObserver(previous)
        }
    }

    /// Idempotent: removes the observer and clears the stored token.
    func tearDown() {
        lock.lock()
        let token = self.token
        self.token = nil
        lock.unlock()
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

private enum NotesTagsProjectionError: Error {
    case fetchFailed(String)
}

/// Tags-only projection shared by the main-context and background paths.
private enum NotesTagsProjection {
    static func uniqueTags(from context: ModelContext) throws -> [String] {
        var descriptor = FetchDescriptor<Note>()
        // No sort — tag aggregation does not care about updatedAt order.
        descriptor.propertiesToFetch = [\.tags]

        let notes: [Note]
        do {
            notes = try context.fetch(descriptor)
        } catch {
            throw NotesTagsProjectionError.fetchFailed(error.localizedDescription)
        }

        var tagSet = Set<String>()
        tagSet.reserveCapacity(notes.count)
        for note in notes {
            tagSet.formUnion(note.tags)
        }
        return tagSet.sorted()
    }
}

/// Background SwiftData projection for unique note tags.
/// Keeps full-library tag aggregation off the main context when callers can await.
@ModelActor
private actor NotesTagsProjectionWorker {
    func uniqueTags() throws -> [String] {
        try NotesTagsProjection.uniqueTags(from: modelContext)
    }
}
