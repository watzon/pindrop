//
//  HistoryStore.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class HistoryStore {
    
    enum HistoryStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case searchFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save transcription: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch transcriptions: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete transcription: \(message)"
            case .searchFailed(let message):
                return "Failed to search transcriptions: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func save(
        text: String,
        duration: TimeInterval,
        modelUsed: String
    ) throws {
        let record = TranscriptionRecord(
            text: text,
            duration: duration,
            modelUsed: modelUsed
        )
        
        modelContext.insert(record)
        
        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func fetchAll() throws -> [TranscriptionRecord] {
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func fetch(limit: Int) throws -> [TranscriptionRecord] {
        var descriptor = FetchDescriptor<TranscriptionRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func delete(_ record: TranscriptionRecord) throws {
        modelContext.delete(record)
        
        do {
            try modelContext.save()
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func deleteAll() throws {
        do {
            try modelContext.delete(model: TranscriptionRecord.self)
            try modelContext.save()
        } catch {
            throw HistoryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func search(query: String) throws -> [TranscriptionRecord] {
        let predicate = #Predicate<TranscriptionRecord> { record in
            record.text.localizedStandardContains(query)
        }
        
        let descriptor = FetchDescriptor<TranscriptionRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw HistoryStoreError.searchFailed(error.localizedDescription)
        }
    }
}
