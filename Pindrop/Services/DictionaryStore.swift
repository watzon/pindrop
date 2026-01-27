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
        case exportFailed(String)
        case importFailed(String)
        
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
            case .exportFailed(let message):
                return "Failed to export dictionary: \(message)"
            case .importFailed(let message):
                return "Failed to import dictionary: \(message)"
            }
        }
    }
    
    enum ImportStrategy {
        case additive  // Add new entries, skip existing
        case replace   // Clear all and import
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
    
    func saveContext() throws {
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.saveFailed(error.localizedDescription)
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
    
    // MARK: - Import/Export
    
    func exportToJSON() throws -> Data {
        let replacements = try fetchAllReplacements()
        let vocabulary = try fetchAllVocabularyWords()
        
        struct ReplacementExport: Codable {
            let originals: [String]
            let replacement: String
            let sortOrder: Int
        }
        
        struct VocabularyExport: Codable {
            let word: String
        }
        
        struct ExportFormat: Codable {
            let version: Int
            let replacements: [ReplacementExport]
            let vocabulary: [VocabularyExport]
            let exportedAt: String
        }
        
        let replacementExports = replacements.map { replacement in
            ReplacementExport(
                originals: replacement.originals,
                replacement: replacement.replacement,
                sortOrder: replacement.sortOrder
            )
        }
        
        let vocabularyExports = vocabulary.map { word in
            VocabularyExport(word: word.word)
        }
        
        let exportData = ExportFormat(
            version: 1,
            replacements: replacementExports,
            vocabulary: vocabularyExports,
            exportedAt: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(exportData)
        } catch {
            throw DictionaryStoreError.exportFailed(error.localizedDescription)
        }
    }
    
    func importFromJSON(_ data: Data, strategy: ImportStrategy) throws {
        struct ReplacementImport: Codable {
            let originals: [String]
            let replacement: String
            let sortOrder: Int
        }
        
        struct VocabularyImport: Codable {
            let word: String
        }
        
        struct ImportFormat: Codable {
            let version: Int
            let replacements: [ReplacementImport]
            let vocabulary: [VocabularyImport]
            let exportedAt: String?
        }
        
        let importData: ImportFormat
        do {
            importData = try JSONDecoder().decode(ImportFormat.self, from: data)
        } catch {
            throw DictionaryStoreError.importFailed("Invalid JSON format: \(error.localizedDescription)")
        }
        
        guard importData.version == 1 else {
            throw DictionaryStoreError.importFailed("Unsupported version: \(importData.version)")
        }
        
        if strategy == .replace {
            let existingReplacements = try fetchAllReplacements()
            for replacement in existingReplacements {
                modelContext.delete(replacement)
            }
            
            let existingVocabulary = try fetchAllVocabularyWords()
            for word in existingVocabulary {
                modelContext.delete(word)
            }
        }
        
        if strategy == .additive {
            let existingReplacements = try fetchAllReplacements()
            let existingOriginals = Set(existingReplacements.flatMap { $0.originals.map { $0.lowercased() } })
            
            for replacementData in importData.replacements {
                let hasOverlap = replacementData.originals.contains { original in
                    existingOriginals.contains(original.lowercased())
                }
                
                if !hasOverlap {
                    let replacement = WordReplacement(
                        originals: replacementData.originals,
                        replacement: replacementData.replacement,
                        sortOrder: replacementData.sortOrder
                    )
                    modelContext.insert(replacement)
                }
            }
            
            let existingVocabulary = try fetchAllVocabularyWords()
            let existingWords = Set(existingVocabulary.map { $0.word.lowercased() })
            
            for vocabularyData in importData.vocabulary {
                if !existingWords.contains(vocabularyData.word.lowercased()) {
                    let word = VocabularyWord(word: vocabularyData.word)
                    modelContext.insert(word)
                }
            }
        } else {
            for replacementData in importData.replacements {
                let replacement = WordReplacement(
                    originals: replacementData.originals,
                    replacement: replacementData.replacement,
                    sortOrder: replacementData.sortOrder
                )
                modelContext.insert(replacement)
            }
            
            for vocabularyData in importData.vocabulary {
                let word = VocabularyWord(word: vocabularyData.word)
                modelContext.insert(word)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            throw DictionaryStoreError.importFailed("Failed to save imported data: \(error.localizedDescription)")
        }
    }
}
