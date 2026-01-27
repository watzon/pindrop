//
//  DictionarySettingsView.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dictionaryStore: DictionaryStore?
    @State private var replacements: [WordReplacement] = []
    @State private var vocabularyWords: [VocabularyWord] = []
    
    // Word Replacement form state
    @State private var originalWords: [String] = []
    @State private var currentOriginalInput: String = ""
    @State private var replacementText: String = ""
    
    // Vocabulary form state
    @State private var vocabularyInput: String = ""
    
    // Error state
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                wordReplacementsSection
                vocabularySection
            }
            .padding()
        }
        .onAppear {
            dictionaryStore = DictionaryStore(modelContext: modelContext)
            loadData()
        }
    }
    
    // MARK: - Word Replacements Section
    
    private var wordReplacementsSection: some View {
        SettingsCard(title: "Word Replacements", icon: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 16) {
                // Add new replacement form
                VStack(alignment: .leading, spacing: 12) {
                    // Original words input (tag-based)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original Words")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        // Tag input field
                        HStack(spacing: 8) {
                            TextField("Type word and press Return", text: $currentOriginalInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addOriginalWord()
                                }
                            
                            Button(action: addOriginalWord) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(currentOriginalInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        
                        // Tags display
                        if !originalWords.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(originalWords, id: \.self) { word in
                                    OriginalWordTag(word: word) {
                                        removeOriginalWord(word)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Replacement text input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Replacement")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("Enter replacement text", text: $replacementText)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: addReplacement) {
                                Text("Add")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!canAddReplacement)
                        }
                    }
                }
                
                Divider()
                
                // Existing replacements list
                if replacements.isEmpty {
                    emptyStateView(
                        icon: "arrow.left.arrow.right",
                        title: "No Replacements",
                        message: "Add word replacements to automatically correct common transcription errors."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(replacements.count) Replacement\(replacements.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 0) {
                            ForEach(Array(replacements.enumerated()), id: \.element.id) { index, replacement in
                                ReplacementRow(
                                    replacement: replacement,
                                    onDelete: { deleteReplacement(replacement) }
                                )
                                
                                if index < replacements.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 12)
                                }
                            }
                        }
                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    // MARK: - Vocabulary Section
    
    private var vocabularySection: some View {
        SettingsCard(title: "Vocabulary", icon: "textformat") {
            VStack(alignment: .leading, spacing: 16) {
                // Add new word form
                HStack(spacing: 8) {
                    TextField("Enter a word to add to vocabulary", text: $vocabularyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addVocabularyWord()
                        }
                    
                    Button(action: addVocabularyWord) {
                        Text("Add")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(vocabularyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                Divider()
                
                // Existing vocabulary display
                if vocabularyWords.isEmpty {
                    emptyStateView(
                        icon: "textformat",
                        title: "No Vocabulary Words",
                        message: "Add custom words to improve transcription accuracy for specialized terms, names, or jargon."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(vocabularyWords.count) Word\(vocabularyWords.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(vocabularyWords) { word in
                                VocabularyTag(word: word) {
                                    deleteVocabularyWord(word)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Computed Properties
    
    private var canAddReplacement: Bool {
        !originalWords.isEmpty && !replacementText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // MARK: - Actions
    
    private func addOriginalWord() {
        let trimmed = currentOriginalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !originalWords.contains(trimmed) else {
            currentOriginalInput = ""
            return
        }
        originalWords.append(trimmed)
        currentOriginalInput = ""
    }
    
    private func removeOriginalWord(_ word: String) {
        originalWords.removeAll { $0 == word }
    }
    
    private func addReplacement() {
        guard canAddReplacement else { return }
        guard let store = dictionaryStore else { return }
        
        do {
            let replacement = WordReplacement(
                originals: originalWords,
                replacement: replacementText.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: replacements.count
            )
            try store.add(replacement)
            
            // Reset form
            originalWords = []
            replacementText = ""
            
            // Reload data
            loadData()
        } catch {
            errorMessage = "Failed to add replacement: \(error.localizedDescription)"
        }
    }
    
    private func deleteReplacement(_ replacement: WordReplacement) {
        guard let store = dictionaryStore else { return }
        
        do {
            try store.delete(replacement)
            loadData()
        } catch {
            errorMessage = "Failed to delete replacement: \(error.localizedDescription)"
        }
    }
    
    private func addVocabularyWord() {
        let trimmed = vocabularyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let store = dictionaryStore else { return }
        
        // Check for duplicates
        guard !vocabularyWords.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) else {
            vocabularyInput = ""
            return
        }
        
        do {
            let word = VocabularyWord(word: trimmed)
            try store.add(word)
            vocabularyInput = ""
            loadData()
        } catch {
            errorMessage = "Failed to add word: \(error.localizedDescription)"
        }
    }
    
    private func deleteVocabularyWord(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        
        do {
            try store.delete(word)
            loadData()
        } catch {
            errorMessage = "Failed to delete word: \(error.localizedDescription)"
        }
    }
    
    private func loadData() {
        guard let store = dictionaryStore else { return }
        
        do {
            replacements = try store.fetchAllReplacements()
            vocabularyWords = try store.fetchAllVocabularyWords()
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Views

struct OriginalWordTag: View {
    let word: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundStyle(.primary)
    }
}

struct VocabularyTag: View {
    let word: VocabularyWord
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(word.word)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.15), in: Capsule())
        .foregroundStyle(.primary)
    }
}

struct ReplacementRow: View {
    let replacement: WordReplacement
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Original words as tags
            FlowLayout(spacing: 6) {
                ForEach(replacement.originals, id: \.self) { original in
                    Text(original)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Replacement text
            Text(replacement.replacement)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(12)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

#Preview {
    DictionarySettingsView()
        .padding()
        .frame(width: 600)
}
