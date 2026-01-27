//
//  DictionarySettingsView.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import SwiftUI
import SwiftData

enum DictionarySection: String, CaseIterable {
    case replacements = "Word Replacements"
    case vocabulary = "Vocabulary"
    
    var icon: String {
        switch self {
        case .replacements:
            return "arrow.left.arrow.right"
        case .vocabulary:
            return "textformat"
        }
    }
    
    var description: String {
        switch self {
        case .replacements:
            return "Define word replacements to automatically replace specific words or phrases"
        case .vocabulary:
            return "Add words to help Pindrop recognize them properly"
        }
    }
    
    var addFormPlaceholder: String {
        switch self {
        case .replacements:
            return "Original text (use commas for multiple)"
        case .vocabulary:
            return "Enter word to add"
        }
    }
    
    var addFormSecondaryPlaceholder: String {
        switch self {
        case .replacements:
            return "Replacement text"
        case .vocabulary:
            return ""
        }
    }
}

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dictionaryStore: DictionaryStore?
    @State private var replacements: [WordReplacement] = []
    @State private var vocabularyWords: [VocabularyWord] = []
    
    // Section selection
    @State private var selectedSection: DictionarySection = .replacements
    
    // Add form state
    @State private var primaryInput: String = ""
    @State private var secondaryInput: String = ""
    
    // Edit state
    @State private var editingReplacement: WordReplacement?
    @State private var editingVocabulary: VocabularyWord?
    @State private var editPrimaryInput: String = ""
    @State private var editSecondaryInput: String = ""
    
    // Error state
    @State private var errorMessage: String?
    @State private var showingImportStrategyDialog = false
    @State private var importDataCache: Data?
    
    // Hover state
    @State private var hoveredRowID: UUID?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Section Selector Tabs
                sectionSelector
                
                // Info Banner
                infoBanner
                
                // Add Form
                addFormSection
                
                // Content Table
                contentTable
            }
            .padding(AppTheme.Spacing.xl)
        }
        .onAppear {
            Log.app.info("DictionarySettingsView appeared, initializing store with modelContext")
            dictionaryStore = DictionaryStore(modelContext: modelContext)
            loadData()
        }
        .alert("Import Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog("Import Strategy", isPresented: $showingImportStrategyDialog) {
            Button("Add to Existing") {
                performImport(strategy: .additive)
            }
            Button("Replace All", role: .destructive) {
                performImport(strategy: .replace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how to import the dictionary data")
        }
    }
    
    // MARK: - Section Selector
    
    private var sectionSelector: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ForEach(DictionarySection.allCases, id: \.self) { section in
                sectionTab(section)
            }
        }
    }
    
    private func sectionTab(_ section: DictionarySection) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                selectedSection = section
            }
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: section.icon)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text(section.rawValue)
                        .font(AppTypography.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Text(section.description)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .fill(selectedSection == section ? AppColors.accent.opacity(0.1) : AppColors.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                    .strokeBorder(
                        selectedSection == section ? AppColors.accent : AppColors.border,
                        lineWidth: selectedSection == section ? 2 : 1
                    )
            )
            .foregroundStyle(selectedSection == section ? AppColors.accent : AppColors.textPrimary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Info Banner
    
    private var infoBanner: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.accent)
            
            Text(selectedSection.description)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
            
            // Import/Export buttons in banner
            HStack(spacing: AppTheme.Spacing.xs) {
                Button(action: handleImport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help("Import Dictionary")
                
                Button(action: handleExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help("Export Dictionary")
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppColors.accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppColors.accent.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Add Form Section
    
    private var addFormSection: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Primary input
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: selectedSection == .replacements ? "text.quote" : "textformat")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                
                TextField(selectedSection.addFormPlaceholder, text: $primaryInput)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppColors.surfaceBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
            
            if selectedSection == .replacements {
                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                
                // Secondary input (replacement)
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    TextField(selectedSection.addFormSecondaryPlaceholder, text: $secondaryInput)
                        .textFieldStyle(.plain)
                        .font(AppTypography.body)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppColors.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
            
            // Add button
            Button(action: handleAdd) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add")
                        .font(AppTypography.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(canAdd ? AppColors.accent : AppColors.textTertiary.opacity(0.3))
            )
            .foregroundStyle(.white)
            .disabled(!canAdd)
        }
    }
    
    private var canAdd: Bool {
        if selectedSection == .replacements {
            return !primaryInput.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !secondaryInput.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !primaryInput.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    // MARK: - Content Table
    
    @ViewBuilder
    private var contentTable: some View {
        switch selectedSection {
        case .replacements:
            replacementsTable
        case .vocabulary:
            vocabularyTable
        }
    }
    
    // MARK: - Replacements Table
    
    private var replacementsTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.md) {
                Text("Original")
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 20)
                
                Text("Replacement")
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Space for actions
                HStack(spacing: AppTheme.Spacing.sm) {
                    Color.clear.frame(width: 28, height: 28)
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.surfaceBackground.opacity(0.5))
            
            Divider()
                .background(AppColors.divider)
            
            // Rows
            if replacements.isEmpty {
                emptyStateView(
                    icon: "arrow.left.arrow.right",
                    title: "No Replacements",
                    message: "Add word replacements to automatically correct common transcription errors."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(replacements.sorted(by: { $0.sortOrder < $1.sortOrder })) { replacement in
                        ReplacementRowNew(
                            replacement: replacement,
                            isEditing: editingReplacement?.id == replacement.id,
                            editOriginals: $editPrimaryInput,
                            editReplacement: $editSecondaryInput,
                            onStartEdit: { startEditingReplacement(replacement) },
                            onSaveEdit: { saveReplacementEdit(replacement) },
                            onCancelEdit: { cancelEditingReplacement() },
                            onDelete: { deleteReplacement(replacement) }
                        )
                        .background(
                            hoveredRowID == replacement.id ? AppColors.surfaceBackground : Color.clear
                        )
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredRowID = isHovered ? replacement.id : nil
                            }
                        }
                        
                        if replacement.id != replacements.last?.id {
                            Divider()
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .background(AppColors.divider)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(AppColors.contentBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Vocabulary Table
    
    private var vocabularyTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: AppTheme.Spacing.md) {
                Text("Word")
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Space for actions
                HStack(spacing: AppTheme.Spacing.sm) {
                    Color.clear.frame(width: 28, height: 28)
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.surfaceBackground.opacity(0.5))
            
            Divider()
                .background(AppColors.divider)
            
            // Rows
            if vocabularyWords.isEmpty {
                emptyStateView(
                    icon: "textformat",
                    title: "No Vocabulary Words",
                    message: "Add custom words to improve transcription accuracy for specialized terms, names, or jargon."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vocabularyWords.sorted(by: { $0.word < $1.word })) { word in
                        VocabularyRowNew(
                            word: word,
                            isEditing: editingVocabulary?.id == word.id,
                            editText: $editPrimaryInput,
                            onStartEdit: { startEditingVocabulary(word) },
                            onSaveEdit: { saveVocabularyEdit(word) },
                            onCancelEdit: { cancelEditingVocabulary() },
                            onDelete: { deleteVocabularyWord(word) }
                        )
                        .background(
                            hoveredRowID == word.id ? AppColors.surfaceBackground : Color.clear
                        )
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredRowID = isHovered ? word.id : nil
                            }
                        }
                        
                        if word.id != vocabularyWords.last?.id {
                            Divider()
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .background(AppColors.divider)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(AppColors.contentBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(title)
                .font(AppTypography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)
            
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxl)
    }
    
    // MARK: - Actions
    
    private func handleAdd() {
        guard let store = dictionaryStore else {
            Log.app.error("DictionaryStore is nil in handleAdd")
            return
        }
        
        switch selectedSection {
        case .replacements:
            // Split by commas for multiple originals
            let originals = primaryInput
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard !originals.isEmpty else {
                Log.app.warning("No originals provided for replacement")
                return
            }
            
            let replacementText = secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.app.info("Adding replacement: \(originals) -> '\(replacementText)'")
            
            do {
                let replacement = WordReplacement(
                    originals: originals,
                    replacement: replacementText,
                    sortOrder: replacements.count
                )
                try store.add(replacement)
                Log.app.info("Replacement added successfully")
                
                // Reset form
                primaryInput = ""
                secondaryInput = ""
                
                // Reload data
                loadData()
            } catch {
                Log.app.error("Failed to add replacement: \(error.localizedDescription)")
                errorMessage = "Failed to add replacement: \(error.localizedDescription)"
            }
            
        case .vocabulary:
            let trimmed = primaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            // Check for duplicates
            guard !vocabularyWords.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) else {
                primaryInput = ""
                return
            }
            
            do {
                let word = VocabularyWord(word: trimmed)
                try store.add(word)
                primaryInput = ""
                loadData()
            } catch {
                errorMessage = "Failed to add word: \(error.localizedDescription)"
            }
        }
    }
    
    private func startEditingReplacement(_ replacement: WordReplacement) {
        editingReplacement = replacement
        editPrimaryInput = replacement.originals.joined(separator: ", ")
        editSecondaryInput = replacement.replacement
    }
    
    private func saveReplacementEdit(_ replacement: WordReplacement) {
        guard let store = dictionaryStore else { return }
        
        let newOriginals = editPrimaryInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !newOriginals.isEmpty else {
            cancelEditingReplacement()
            return
        }
        
        do {
            replacement.originals = newOriginals
            replacement.replacement = editSecondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.saveContext()
            cancelEditingReplacement()
            loadData()
        } catch {
            errorMessage = "Failed to update replacement: \(error.localizedDescription)"
        }
    }
    
    private func cancelEditingReplacement() {
        editingReplacement = nil
        editPrimaryInput = ""
        editSecondaryInput = ""
    }
    
    private func startEditingVocabulary(_ word: VocabularyWord) {
        editingVocabulary = word
        editPrimaryInput = word.word
    }
    
    private func saveVocabularyEdit(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        
        let trimmed = editPrimaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelEditingVocabulary()
            return
        }
        
        let isDuplicate = vocabularyWords.contains {
            $0.id != word.id && $0.word.lowercased() == trimmed.lowercased()
        }
        
        guard !isDuplicate else {
            cancelEditingVocabulary()
            return
        }
        
        do {
            word.word = trimmed
            try store.saveContext()
            cancelEditingVocabulary()
            loadData()
        } catch {
            errorMessage = "Failed to update word: \(error.localizedDescription)"
        }
    }
    
    private func cancelEditingVocabulary() {
        editingVocabulary = nil
        editPrimaryInput = ""
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
        guard let store = dictionaryStore else {
            Log.app.error("DictionaryStore is nil in loadData")
            return
        }
        
        do {
            replacements = try store.fetchAllReplacements()
            vocabularyWords = try store.fetchAllVocabularyWords()
            Log.app.info("Loaded \(replacements.count) replacements and \(vocabularyWords.count) vocabulary words")
        } catch {
            Log.app.error("Failed to load dictionary data: \(error.localizedDescription)")
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
    
    private func handleExport() {
        guard let store = dictionaryStore else { return }
        
        do {
            let jsonData = try store.exportToJSON()
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "dictionary.json"
            savePanel.title = "Export Dictionary"
            savePanel.message = "Choose a location to save the dictionary"
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
            }
        } catch {
            errorMessage = "Failed to export dictionary: \(error.localizedDescription)"
        }
    }
    
    private func handleImport() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.title = "Import Dictionary"
        openPanel.message = "Select a dictionary JSON file to import"
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                
                let decoder = JSONDecoder()
                _ = try decoder.decode(DictionaryImportPreview.self, from: data)
                
                showingImportStrategyDialog = true
                importDataCache = data
            } catch {
                errorMessage = "Failed to read import file: \(error.localizedDescription)"
            }
        }
    }
    
    private func performImport(strategy: DictionaryStore.ImportStrategy) {
        guard let store = dictionaryStore, let data = importDataCache else { return }
        
        do {
            try store.importFromJSON(data, strategy: strategy)
            loadData()
            importDataCache = nil
        } catch {
            errorMessage = "Failed to import dictionary: \(error.localizedDescription)"
        }
    }
}

// MARK: - Dictionary Import Preview

struct DictionaryImportPreview: Codable {
    let version: Int
    let replacements: [ReplacementPreview]
    let vocabulary: [VocabularyPreview]
    
    struct ReplacementPreview: Codable {
        let originals: [String]
        let replacement: String
    }
    
    struct VocabularyPreview: Codable {
        let word: String
    }
}

// MARK: - Replacement Row

struct ReplacementRowNew: View {
    let replacement: WordReplacement
    let isEditing: Bool
    @Binding var editOriginals: String
    @Binding var editReplacement: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if isEditing {
                // Edit mode
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField("Originals (comma-separated)", text: $editOriginals)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.bodySmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 20)
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField("Replacement", text: $editReplacement)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.bodySmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Save/Cancel buttons
                HStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onSaveEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.success)
                    .frame(width: 28, height: 28)
                    .background(AppColors.success.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    
                    Button(action: onCancelEdit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                }
            } else {
                // Display mode
                // Original words
                FlowLayout(spacing: 6) {
                    ForEach(replacement.originals, id: \.self) { original in
                        Text(original)
                            .font(AppTypography.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.accent.opacity(0.15))
                            .foregroundStyle(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 20)
                
                // Replacement text
                Text(replacement.replacement)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Action buttons (visible on hover)
                HStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onStartEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? AppColors.elevatedSurface : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .opacity(isHovered ? 1 : 0)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.error)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? AppColors.error.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Vocabulary Row

struct VocabularyRowNew: View {
    let word: VocabularyWord
    let isEditing: Bool
    @Binding var editText: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if isEditing {
                // Edit mode
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField("Word", text: $editText)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.bodySmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Save/Cancel buttons
                HStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onSaveEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.success)
                    .frame(width: 28, height: 28)
                    .background(AppColors.success.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    
                    Button(action: onCancelEdit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                }
            } else {
                // Display mode
                Text(word.word)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Action buttons (visible on hover)
                HStack(spacing: AppTheme.Spacing.xs) {
                    Button(action: onStartEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? AppColors.elevatedSurface : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .opacity(isHovered ? 1 : 0)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.error)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? AppColors.error.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
        .frame(width: 700, height: 600)
}
