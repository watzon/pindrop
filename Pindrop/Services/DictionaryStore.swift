//
//  DictionaryStore.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import SwiftData

struct LearnedReplacementChange: Equatable {
    let replacementID: UUID
    let replacement: String
    let learnedOriginal: String
    let createdReplacement: Bool
}

@MainActor
protocol LearnedReplacementPersisting: AnyObject {
    func upsertLearnedReplacement(original: String, replacement: String) throws -> LearnedReplacementChange?
    func undoLearnedReplacement(_ change: LearnedReplacementChange) throws
}

@MainActor
@Observable
final class DictionaryStore: LearnedReplacementPersisting {
    
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

    func upsertLearnedReplacement(original: String, replacement: String) throws -> LearnedReplacementChange? {
        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedOriginal.isEmpty, !normalizedReplacement.isEmpty else {
            return nil
        }

        let replacements = try fetchAllReplacements()
        if let existing = replacements.first(where: {
            $0.replacement.compare(normalizedReplacement, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            let alreadyLearned = existing.originals.contains {
                $0.compare(normalizedOriginal, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard !alreadyLearned else {
                return nil
            }

            existing.originals.append(normalizedOriginal)
            try saveContext()

            return LearnedReplacementChange(
                replacementID: existing.id,
                replacement: existing.replacement,
                learnedOriginal: normalizedOriginal,
                createdReplacement: false
            )
        }

        let nextSortOrder = (replacements.map(\.sortOrder).max() ?? -1) + 1
        let learnedReplacement = WordReplacement(
            originals: [normalizedOriginal],
            replacement: normalizedReplacement,
            sortOrder: nextSortOrder
        )
        try add(learnedReplacement)

        return LearnedReplacementChange(
            replacementID: learnedReplacement.id,
            replacement: learnedReplacement.replacement,
            learnedOriginal: normalizedOriginal,
            createdReplacement: true
        )
    }

    func undoLearnedReplacement(_ change: LearnedReplacementChange) throws {
        let replacement = try resolveReplacement(for: change)
        guard let replacement else { return }

        replacement.originals.removeAll {
            $0.compare(change.learnedOriginal, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }

        if replacement.originals.isEmpty {
            try delete(replacement)
        } else {
            try saveContext()
        }
    }
    
    // MARK: - Text Replacement
    
    /// Applies word replacements in persisted `sortOrder` (ascending).
    ///
    /// **Ordering (behavior change):** Rules are applied earliest-`sortOrder` first.
    /// A span consumed by an earlier rule is not re-matched by later rules
    /// ("first match wins"). This replaces the previous longest-match-first sort.
    ///
    /// Match modes:
    /// - `.caseInsensitive` — word-boundary, case-insensitive (historical default)
    /// - `.exact` — word-boundary, case-sensitive
    /// - `.command` — word-boundary, case-insensitive spoken phrase → control sequence
    ///   via ``ReplacementCommandPalette``
    ///
    /// When a rule produces at least one substitution, its `usageCount` is incremented
    /// by the number of substitutions (when `trackUsage` is true). Usage is batched into a single save.
    /// - Parameters:
    ///   - text: The input text to process
    ///   - trackUsage: When false, skips usageCount updates (for intermediate/discarded passes)
    /// - Returns: A tuple containing the modified text and a list of applied replacements
    func applyReplacements(
        to text: String,
        trackUsage: Bool = true
    ) throws -> (String, [(original: String, replacement: String)]) {
        guard !text.isEmpty else {
            return (text, [])
        }
        
        // Already ordered by sortOrder ascending from fetchAllReplacements().
        let replacements = try fetchAllReplacements()
        guard !replacements.isEmpty else {
            return (text, [])
        }
        
        // Work on NSString / UTF-16 offsets so consumed spans stay valid across mutations.
        var result = text as NSString
        var appliedReplacements: [(original: String, replacement: String)] = []
        var consumedUTF16: [NSRange] = []
        var usageDeltas: [UUID: Int] = [:]
        
        for rule in replacements {
            let substitution = substitutionText(for: rule)
            let caseInsensitive = rule.matchMode != .exact
            var ruleHitCount = 0
            
            for original in rule.originals {
                let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedOriginal.isEmpty else { continue }
                
                guard let regex = try? Self.tokenBoundaryRegex(
                    for: trimmedOriginal,
                    caseInsensitive: caseInsensitive
                ) else {
                    continue
                }
                
                let fullRange = NSRange(location: 0, length: result.length)
                let matches = regex.matches(in: result as String, options: [], range: fullRange)
                
                // Reverse order keeps later UTF-16 offsets stable as we mutate `result`.
                for match in matches.reversed() {
                    let matchRange = match.range
                    guard matchRange.location != NSNotFound else { continue }
                    
                    let overlaps = consumedUTF16.contains { NSIntersectionRange($0, matchRange).length > 0 }
                    guard !overlaps else { continue }
                    
                    let matchedText = result.substring(with: matchRange)
                    result = result.replacingCharacters(in: matchRange, with: substitution) as NSString
                    appliedReplacements.append((original: matchedText, replacement: substitution))
                    ruleHitCount += 1
                    
                    let delta = (substitution as NSString).length - matchRange.length
                    consumedUTF16 = consumedUTF16.map { range in
                        if range.location >= matchRange.location + matchRange.length {
                            return NSRange(location: range.location + delta, length: range.length)
                        }
                        return range
                    }
                    consumedUTF16.append(NSRange(location: matchRange.location, length: (substitution as NSString).length))
                }
            }
            
            if ruleHitCount > 0 {
                usageDeltas[rule.id, default: 0] += ruleHitCount
            }
        }
        
        if trackUsage, !usageDeltas.isEmpty {
            for rule in replacements {
                if let delta = usageDeltas[rule.id] {
                    rule.usageCount += delta
                }
            }
            try saveContext()
        }
        
        return (result as String, appliedReplacements)
    }

    /// Counts case-insensitive word-boundary occurrences of each vocabulary entry in
    /// `text` and increments `usageCount` by the hit count. Batches into a single save.
    func recordVocabularyHits(in text: String) throws {
        guard !text.isEmpty else { return }

        let words = try fetchAllVocabularyWords()
        guard !words.isEmpty else { return }

        var didChange = false
        for entry in words {
            let trimmed = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let hits = Self.wordBoundaryMatchCount(of: trimmed, in: text, caseInsensitive: true)
            if hits > 0 {
                entry.usageCount += hits
                didChange = true
            }
        }

        if didChange {
            try saveContext()
        }
    }

    /// Top vocabulary words for WhisperKit prompt biasing (highest usage, then newest).
    func vocabularyBiasWords(limit: Int = VocabularyBiasPrompt.maxWordCount) throws -> [String] {
        let words = try fetchAllVocabularyWords()
        let entries = words.map {
            VocabularyBiasPrompt.Entry(word: $0.word, usageCount: $0.usageCount, createdAt: $0.createdAt)
        }
        return VocabularyBiasPrompt.selectWords(from: entries, limit: limit)
    }

    private func substitutionText(for rule: WordReplacement) -> String {
        switch rule.matchMode {
        case .command:
            return ReplacementCommandPalette.resolve(rule.replacement)
        case .caseInsensitive, .exact:
            return rule.replacement
        }
    }

    /// Word-boundary match count for vocabulary hit tracking / tests.
    static func wordBoundaryMatchCount(
        of pattern: String,
        in text: String,
        caseInsensitive: Bool
    ) -> Int {
        guard let regex = try? tokenBoundaryRegex(for: pattern, caseInsensitive: caseInsensitive) else {
            return 0
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, options: [], range: nsRange)
    }

    /// Token-boundary regex for dictionary patterns.
    ///
    /// Uses lookarounds `(?<!\w)…(?!\w)` instead of `\b…\b`. Classic `\b` is a
    /// word/non-word *transition*, so patterns that end with punctuation (e.g. `C++`)
    /// fail to match when followed by whitespace (no transition) and spuriously match
    /// prefixes of `C++abi` (punctuation→letter *is* a transition). Lookarounds enforce
    /// "not adjacent to a word character", which matches alphanumeric tokens the same
    /// as `\b` and treats punctuated tokens sanely.
    static func tokenBoundaryRegex(
        for pattern: String,
        caseInsensitive: Bool
    ) throws -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "(?<!\\w)\(escaped)(?!\\w)"
        var options: NSRegularExpression.Options = []
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        return try NSRegularExpression(pattern: regexPattern, options: options)
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

    private func resolveReplacement(for change: LearnedReplacementChange) throws -> WordReplacement? {
        let replacements = try fetchAllReplacements()
        if let exactMatch = replacements.first(where: { $0.id == change.replacementID }) {
            return exactMatch
        }

        return replacements.first(where: {
            $0.replacement.compare(change.replacement, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }
}
