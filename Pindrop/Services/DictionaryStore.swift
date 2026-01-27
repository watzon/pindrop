//
//  DictionaryStore.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class DictionaryStore {
    
    enum DictionaryStoreError: Error, LocalizedError {
        case saveFailed(String)
        case fetchFailed(String)
        case deleteFailed(String)
        case replacementFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "Failed to save dictionary entry: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch dictionary entries: \(message)"
            case .deleteFailed(let message):
                return "Failed to delete dictionary entry: \(message)"
            case .replacementFailed(let message):
                return "Failed to apply replacements: \(message)"
            }
        }
    }
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - WordReplacement CRUD
    
    func fetchAllReplacements() throws -> [WordReplacement] {
        let descriptor = FetchDescriptor<WordReplacement>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw DictionaryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func add(_ replacement: WordReplacement) throws {
        modelContext.insert(replacement)
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func delete(_ replacement: WordReplacement) throws {
        modelContext.delete(replacement)
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    func reorder(_ replacements: [WordReplacement], from source: IndexSet, to destination: Int) throws {
        var reordered = replacements
        reordered.move(fromOffsets: source, toOffset: destination)
        
        // Update sortOrder for all items
        for (index, replacement) in reordered.enumerated() {
            replacement.sortOrder = index
        }
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    // MARK: - VocabularyWord CRUD
    
    func fetchAllVocabularyWords() throws -> [VocabularyWord] {
        let descriptor = FetchDescriptor<VocabularyWord>(
            sortBy: [SortDescriptor(\.word, order: .forward)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw DictionaryStoreError.fetchFailed(error.localizedDescription)
        }
    }
    
    func add(_ word: VocabularyWord) throws {
        modelContext.insert(word)
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.saveFailed(error.localizedDescription)
        }
    }
    
    func delete(_ word: VocabularyWord) throws {
        modelContext.delete(word)
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.deleteFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Text Replacement
    
    /// Applies word replacements to the given text using word boundary matching.
    /// - Parameter text: The input text to process
    /// - Returns: A tuple containing the modified text and a list of applied replacements
    func applyReplacements(to text: String) throws -> (String, [(original: String, replacement: String)]) {
        guard !text.isEmpty else {
            return (text, [])
        }
        
        let replacements = try fetchAllReplacements()
        guard !replacements.isEmpty else {
            return (text, [])
        }
        
        // Flatten all originals with their replacements and sort by length (longest first)
        var patterns: [(original: String, replacement: String)] = []
        for replacement in replacements {
            for original in replacement.originals {
                patterns.append((original: original, replacement: replacement.replacement))
            }
        }
        patterns.sort { $0.original.count > $1.original.count }
        
        var result = text
        var appliedReplacements: [(original: String, replacement: String)] = []
        var replacedRanges: [Range<String.Index>] = []
        
        // Single pass: process each pattern
        for pattern in patterns {
            let original = pattern.original
            let replacement = pattern.replacement
            
            // Escape special regex characters in the original string
            let escapedOriginal = NSRegularExpression.escapedPattern(for: original)
            
            // Create regex with word boundaries and case-insensitive matching
            let regexPattern = "\\b\(escapedOriginal)\\b"
            
            guard let regex = try? NSRegularExpression(
                pattern: regexPattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: nsRange)
            
            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else {
                    continue
                }
                
                // Check if this range overlaps with any already replaced range
                let overlaps = replacedRanges.contains { existingRange in
                    matchRange.overlaps(existingRange)
                }
                
                if !overlaps {
                    let matchedText = String(result[matchRange])
                    result.replaceSubrange(matchRange, with: replacement)
                    appliedReplacements.append((original: matchedText, replacement: replacement))
                    
                    let newStart = matchRange.lowerBound
                    let newEnd = result.index(newStart, offsetBy: replacement.count)
                    replacedRanges.append(newStart..<newEnd)
                }
            }
        }
        
        return (result, appliedReplacements)
    }
}
