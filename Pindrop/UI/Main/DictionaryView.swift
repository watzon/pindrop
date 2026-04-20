//
//  DictionaryView.swift
//  Pindrop
//
//  Main window view for dictionary management
//

import SwiftUI
import SwiftData
import Foundation

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

    func title(locale: Locale) -> String {
        localized(rawValue, locale: locale)
    }

    func bannerDescription(locale: Locale) -> String {
        switch self {
        case .replacements:
            return localized("Define word replacements to automatically replace specific words or phrases", locale: locale)
        case .vocabulary:
            return localized("Add words to help Pindrop recognize them properly", locale: locale)
        }
    }

    func tabDescription(locale: Locale) -> String {
        switch self {
        case .replacements:
            return localized("Replace words and phrases", locale: locale)
        case .vocabulary:
            return localized("Teach custom words", locale: locale)
        }
    }

    func addFormPlaceholder(locale: Locale) -> String {
        switch self {
        case .replacements:
            return localized("Original text (use commas for multiple)", locale: locale)
        case .vocabulary:
            return localized("Enter word to add", locale: locale)
        }
    }

    func addFormSecondaryPlaceholder(locale: Locale) -> String {
        switch self {
        case .replacements:
            return localized("Replacement text", locale: locale)
        case .vocabulary:
            return ""
        }
    }
}

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
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
    
    private var totalItemCount: Int {
        replacements.count + vocabularyWords.count
    }
    
    var body: some View {
        MainContentPageLayout(scrollContent: false) {
            headerSection
        } content: {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            Log.app.info("DictionaryView appeared, initializing store with modelContext")
            dictionaryStore = DictionaryStore(modelContext: modelContext)
            loadData()
        }
        .alert(localized("Import Error", locale: locale), isPresented: .constant(errorMessage != nil)) {
            Button(localized("OK", locale: locale)) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(localized("Import Strategy", locale: locale), isPresented: $showingImportStrategyDialog) {
            Button(localized("Add to Existing", locale: locale)) {
                performImport(strategy: .additive)
            }
            Button(localized("Replace All", locale: locale), role: .destructive) {
                performImport(strategy: .replace)
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(localized("Choose how to import the dictionary data", locale: locale))
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(localized("Dictionary", locale: locale))
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(totalItemCount) \(localized("items", locale: locale))")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Menu {
                    Button(action: handleImport) {
                        Label(localized("Import Dictionary", locale: locale), systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: handleExport) {
                        Label(localized("Export Dictionary", locale: locale), systemImage: "square.and.arrow.up")
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(localized("Import/Export", locale: locale))
                    }
                    .font(AppTypography.subheadline)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .menuStyle(.borderlessButton)
            }
            
            // Section selector tabs
            sectionSelector
            
            // Add form
            addFormSection
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
                    
                    Text(section.title(locale: locale))
                        .font(AppTypography.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                Text(section.tabDescription(locale: locale))
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
    
    // MARK: - Add Form Section
    
    private var addFormSection: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Primary input
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: selectedSection == .replacements ? "text.quote" : "textformat")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                
                TextField(selectedSection.addFormPlaceholder(locale: locale), text: $primaryInput)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppColors.surfaceBackground)
            )
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md),
                style: AppColors.border
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
                    
                    TextField(selectedSection.addFormSecondaryPlaceholder(locale: locale), text: $secondaryInput)
                        .textFieldStyle(.plain)
                        .font(AppTypography.body)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .fill(AppColors.surfaceBackground)
                )
                .hairlineBorder(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md),
                    style: AppColors.border
                )
            }
            
            // Add button
            Button(action: handleAdd) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(localized("Add", locale: locale))
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
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage = errorMessage {
            errorView(errorMessage)
        } else if isContentEmpty {
            emptyStateView
        } else {
            contentTable
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
    
    private var isContentEmpty: Bool {
        switch selectedSection {
        case .replacements:
            return replacements.isEmpty
        case .vocabulary:
            return vocabularyWords.isEmpty
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
            
            Text(localized("Something went wrong", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(localized("Dismiss", locale: locale)) {
                self.errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: selectedSection == .replacements ? "arrow.left.arrow.right" : "textformat")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(selectedSection == .replacements
                 ? localized("No Replacements", locale: locale)
                 : localized("No Vocabulary Words", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(selectedSection == .replacements
                 ? localized("Add word replacements to automatically correct common transcription errors.", locale: locale)
                 : localized("Add custom words to improve transcription accuracy for specialized terms, names, or jargon.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(localized("Original", locale: locale))
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 20)
                
                Text(localized("Replacement", locale: locale))
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(replacements.sorted(by: { $0.sortOrder < $1.sortOrder })) { replacement in
                        ReplacementRow(
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
            style: AppColors.border
        )
    }

    private var vocabularyTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(localized("Word", locale: locale))
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vocabularyWords.sorted(by: { $0.word < $1.word })) { word in
                        VocabularyRow(
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
            style: AppColors.border
        )
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
            Log.app.info("Adding dictionary replacement (sourceCount=\(originals.count), replacementLength=\(replacementText.count))")
            
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
                errorMessage = localized("Failed to add replacement: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
                errorMessage = localized("Failed to add word: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to update replacement: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to update word: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to delete replacement: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
    
    private func deleteVocabularyWord(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        
        do {
            try store.delete(word)
            loadData()
        } catch {
            errorMessage = localized("Failed to delete word: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to load data: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
    
    private func handleExport() {
        guard let store = dictionaryStore else { return }
        
        do {
            let jsonData = try store.exportToJSON()
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "dictionary.json"
            let currentLocale = locale
            savePanel.title = localized("Export Dictionary", locale: currentLocale)
            savePanel.message = localized("Choose a location to save the dictionary", locale: currentLocale)
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
            }
        } catch {
            errorMessage = localized("Failed to export dictionary: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
    
    private func handleImport() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        let currentLocale = locale
        openPanel.title = localized("Import Dictionary", locale: currentLocale)
        openPanel.message = localized("Select a dictionary JSON file to import", locale: currentLocale)
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                
                let decoder = JSONDecoder()
                _ = try decoder.decode(DictionaryImportPreview.self, from: data)
                
                showingImportStrategyDialog = true
                importDataCache = data
            } catch {
                errorMessage = localized("Failed to read import file: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to import dictionary: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
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

struct ReplacementRow: View {
    let replacement: WordReplacement
    let isEditing: Bool
    @Binding var editOriginals: String
    @Binding var editReplacement: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.locale) private var locale
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if isEditing {
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField(localized("Originals (comma-separated)", locale: locale), text: $editOriginals)
                        .textFieldStyle(.roundedBorder)
                        .font(AppTypography.bodySmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 20)
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField(localized("Replacement", locale: locale), text: $editReplacement)
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

struct VocabularyRow: View {
    let word: VocabularyWord
    let isEditing: Bool
    @Binding var editText: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.locale) private var locale
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if isEditing {
                HStack(spacing: AppTheme.Spacing.sm) {
                    TextField(localized("Word", locale: locale), text: $editText)
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

// MARK: - Preview

#Preview("Dictionary View - Empty") {
    DictionaryView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.light)
}

#Preview("Dictionary View - Dark") {
    DictionaryView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}
