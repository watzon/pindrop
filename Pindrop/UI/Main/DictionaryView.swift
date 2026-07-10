//
//  DictionaryView.swift
//  Pindrop
//
//  Dictionary page (U6 scorched-earth restyle, spec §11).
//

import SwiftUI
import SwiftData
import Foundation
import AppKit

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @State private var dictionaryStore: DictionaryStore?
    @State private var replacements: [WordReplacement] = []
    @State private var vocabularyWords: [VocabularyWord] = []

    // Add / edit sheets
    @State private var showAddWordSheet = false
    @State private var showAddReplacementSheet = false
    @State private var primaryInput: String = ""
    @State private var secondaryInput: String = ""
    @State private var addMatchMode: ReplacementMatchMode = .caseInsensitive

    @State private var editingReplacement: WordReplacement?
    @State private var editingVocabulary: VocabularyWord?
    @State private var editPrimaryInput: String = ""
    @State private var editSecondaryInput: String = ""
    @State private var editMatchMode: ReplacementMatchMode = .caseInsensitive

    @State private var errorMessage: String?
    @State private var showingImportStrategyDialog = false
    @State private var importDataCache: Data?

    @State private var selectedRowID: UUID?
    @State private var keyMonitor: Any?

    private var orderedVocabulary: [VocabularyWord] {
        // Sort models directly — never uniquing by lowercased key (duplicates trap).
        DictionaryVocabularyOrdering.sortedModels(vocabularyWords)
    }

    private var orderedReplacements: [WordReplacement] {
        replacements.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var orderedSelectableIDs: [UUID] {
        orderedReplacements.map(\.id) + orderedVocabulary.map(\.id)
    }

    private var isCompletelyEmpty: Bool {
        replacements.isEmpty && vocabularyWords.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isCompletelyEmpty {
                        emptyStateView
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        vocabularySection
                        replacementsSection
                        footnote
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                    }
                    Color.clear.frame(height: 32)
                }
                .padding(.bottom, 24)
            }
            .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
        .onAppear {
            dictionaryStore = DictionaryStore(modelContext: modelContext)
            loadData()
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
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
        .sheet(isPresented: $showAddWordSheet) {
            addWordSheet
        }
        .sheet(isPresented: $showAddReplacementSheet) {
            addReplacementSheet
        }
        .sheet(isPresented: Binding(
            get: { editingVocabulary != nil },
            set: { if !$0 { editingVocabulary = nil } }
        )) {
            if let word = editingVocabulary {
                editVocabularySheet(word)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingReplacement != nil },
            set: { if !$0 { editingReplacement = nil } }
        )) {
            if let replacement = editingReplacement {
                editReplacementSheet(replacement)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        PageHeader(
            title: localized("Dictionary", locale: locale),
            meta: localized("Teach Pindrop your words", locale: locale)
        ) {
            HStack(spacing: 10) {
                Menu {
                    Button(action: handleImport) {
                        Label(localized("Import Dictionary", locale: locale), systemImage: "square.and.arrow.down")
                    }
                    Button(action: handleExport) {
                        Label(localized("Export Dictionary", locale: locale), systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button {
                        primaryInput = ""
                        secondaryInput = ""
                        addMatchMode = .caseInsensitive
                        showAddReplacementSheet = true
                    } label: {
                        Label(localized("Add replacement", locale: locale), systemImage: "arrow.left.arrow.right")
                    }
                } label: {
                    SecondaryButton(
                        title: localized("Import/Export", locale: locale),
                        systemImage: "ellipsis",
                        action: {}
                    )
                    .allowsHitTesting(false)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                PrimaryButton(
                    title: localized("Add word", locale: locale),
                    systemImage: "plus",
                    action: {
                        primaryInput = ""
                        showAddWordSheet = true
                    }
                )
            }
        }
    }

    // MARK: - Vocabulary section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: localized("Vocabulary", locale: locale),
                trailing: localized("Words the recognizer should trust", locale: locale),
                isFirst: true
            )
            .padding(.horizontal, 20)

            FlowLayout(spacing: 8) {
                ForEach(orderedVocabulary) { word in
                    vocabularyChip(word)
                }
                addVocabularyChip
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func vocabularyChip(_ word: VocabularyWord) -> some View {
        let isSelected = selectedRowID == word.id
        return Button {
            selectedRowID = word.id
        } label: {
            HStack(spacing: 7) {
                Text(word.word)
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(word.usageCount)")
                    .font(FontLoader.font(family: .jetbrainsMono, size: 10, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(AppColors.windowBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? AppColors.accent.opacity(0.55) : AppColors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(Capsule(style: .continuous))
        .contextMenu {
            Button {
                startEditingVocabulary(word)
            } label: {
                Label(localized("Edit", locale: locale), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteVocabularyWord(word)
            } label: {
                Label(localized("Delete", locale: locale), systemImage: "trash")
            }
        }
        .onTapGesture(count: 2) {
            startEditingVocabulary(word)
        }
    }

    private var addVocabularyChip: some View {
        Button {
            primaryInput = ""
            showAddWordSheet = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                Text(localized("Add", locale: locale))
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .overlay(
                Capsule()
                    .strokeBorder(
                        AppColors.border,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(Capsule(style: .continuous))
    }

    // MARK: - Replacements section

    private var replacementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: localized("Replacements", locale: locale),
                trailing: localized("Applied after transcription, before insert", locale: locale),
                isFirst: false
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            if orderedReplacements.isEmpty {
                Text(localized("No Replacements", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            } else {
                // List enables drag-to-reorder (onMove) wired to DictionaryStore.reorder.
                List {
                    ForEach(orderedReplacements) { replacement in
                        replacementRow(replacement)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: moveReplacements)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: CGFloat(orderedReplacements.count) * 48)
                .environment(\.defaultMinListRowHeight, 44)
            }
        }
    }

    private func replacementRow(_ replacement: WordReplacement) -> some View {
        let isSelected = selectedRowID == replacement.id
        let pattern = DictionaryCommandTokenDisplay.patternDisplay(originals: replacement.originals)
        let value = DictionaryCommandTokenDisplay.replacementDisplay(
            replacement: replacement.replacement,
            matchMode: replacement.matchMode
        )
        let modeLabel = DictionaryMatchModeLabel.label(for: replacement.matchMode, locale: locale)

        return Button {
            selectedRowID = replacement.id
        } label: {
            HStack(spacing: 14) {
                Text(pattern)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 14, height: 14)
                    .flipsForRightToLeftLayoutDirection(true)

                Text(value)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(modeLabel)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(isSelected ? AppColors.accent.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                startEditingReplacement(replacement)
            } label: {
                Label(localized("Edit", locale: locale), systemImage: "pencil")
            }
            Menu(localized("Match mode", locale: locale)) {
                ForEach([ReplacementMatchMode.caseInsensitive, .exact, .command], id: \.rawValue) { mode in
                    Button {
                        setMatchMode(replacement, mode: mode)
                    } label: {
                        if replacement.matchMode == mode {
                            Label(DictionaryMatchModeLabel.label(for: mode, locale: locale), systemImage: "checkmark")
                        } else {
                            Text(DictionaryMatchModeLabel.label(for: mode, locale: locale))
                        }
                    }
                }
            }
            Button(role: .destructive) {
                deleteReplacement(replacement)
            } label: {
                Label(localized("Delete", locale: locale), systemImage: "trash")
            }
        }
        .onTapGesture(count: 2) {
            startEditingReplacement(replacement)
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
            Text(localized("Replacements run in order. Drag rows to re-order — the first match wins.", locale: locale))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("No dictionary entries", locale: locale))
                .font(AppTypography.labelStrong)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Add words the recognizer should trust, or replacements applied after transcription.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            PrimaryButton(
                title: localized("Add word", locale: locale),
                systemImage: "plus",
                action: {
                    primaryInput = ""
                    showAddWordSheet = true
                }
            )
            .padding(.top, 4)
        }
    }

    // MARK: - Sheets

    private var addWordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Add word", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Enter word to add", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    showAddWordSheet = false
                }
                PrimaryButton(
                    title: localized("Add", locale: locale),
                    isEnabled: !primaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: {
                        handleAddWord()
                        showAddWordSheet = false
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(AppColors.contentBackground)
    }

    private var addReplacementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Add replacement", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Original text (use commas for multiple)", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            TextField(localized("Replacement text", locale: locale), text: $secondaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            Picker(localized("Match mode", locale: locale), selection: $addMatchMode) {
                Text(DictionaryMatchModeLabel.label(for: .caseInsensitive, locale: locale))
                    .tag(ReplacementMatchMode.caseInsensitive)
                Text(DictionaryMatchModeLabel.label(for: .exact, locale: locale))
                    .tag(ReplacementMatchMode.exact)
                Text(DictionaryMatchModeLabel.label(for: .command, locale: locale))
                    .tag(ReplacementMatchMode.command)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    showAddReplacementSheet = false
                }
                PrimaryButton(
                    title: localized("Add", locale: locale),
                    isEnabled: canAddReplacement,
                    action: {
                        handleAddReplacement()
                        showAddReplacementSheet = false
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(AppColors.contentBackground)
    }

    private func editVocabularySheet(_ word: VocabularyWord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Edit", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Word", locale: locale), text: $editPrimaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    editingVocabulary = nil
                }
                PrimaryButton(
                    title: localized("Save", locale: locale),
                    action: {
                        saveVocabularyEdit(word)
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(AppColors.contentBackground)
        .onAppear {
            editPrimaryInput = word.word
        }
    }

    private func editReplacementSheet(_ replacement: WordReplacement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Edit", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Originals (comma-separated)", locale: locale), text: $editPrimaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            TextField(localized("Replacement", locale: locale), text: $editSecondaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            Picker(localized("Match mode", locale: locale), selection: $editMatchMode) {
                Text(DictionaryMatchModeLabel.label(for: .caseInsensitive, locale: locale))
                    .tag(ReplacementMatchMode.caseInsensitive)
                Text(DictionaryMatchModeLabel.label(for: .exact, locale: locale))
                    .tag(ReplacementMatchMode.exact)
                Text(DictionaryMatchModeLabel.label(for: .command, locale: locale))
                    .tag(ReplacementMatchMode.command)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    editingReplacement = nil
                }
                PrimaryButton(
                    title: localized("Save", locale: locale),
                    action: {
                        saveReplacementEdit(replacement)
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(AppColors.contentBackground)
        .onAppear {
            editPrimaryInput = replacement.originals.joined(separator: ", ")
            editSecondaryInput = replacement.replacement
            editMatchMode = replacement.matchMode
        }
    }

    private var canAddReplacement: Bool {
        !primaryInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !secondaryInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func handleAddWord() {
        guard let store = dictionaryStore else { return }
        let trimmed = primaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !vocabularyWords.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) else {
            primaryInput = ""
            return
        }
        do {
            try store.add(VocabularyWord(word: trimmed))
            primaryInput = ""
            loadData()
        } catch {
            errorMessage = localized("Failed to add word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func handleAddReplacement() {
        guard let store = dictionaryStore else { return }
        let originals = primaryInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !originals.isEmpty else { return }
        let replacementText = secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let replacement = WordReplacement(
                originals: originals,
                replacement: replacementText,
                sortOrder: replacements.count,
                matchModeRawValue: addMatchMode.rawValue
            )
            try store.add(replacement)
            primaryInput = ""
            secondaryInput = ""
            loadData()
        } catch {
            errorMessage = localized("Failed to add replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func startEditingReplacement(_ replacement: WordReplacement) {
        editingReplacement = replacement
    }

    private func startEditingVocabulary(_ word: VocabularyWord) {
        editingVocabulary = word
    }

    private func saveReplacementEdit(_ replacement: WordReplacement) {
        guard let store = dictionaryStore else { return }
        let newOriginals = editPrimaryInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !newOriginals.isEmpty else {
            editingReplacement = nil
            return
        }
        do {
            replacement.originals = newOriginals
            replacement.replacement = editSecondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
            replacement.matchModeRawValue = editMatchMode.rawValue
            try store.saveContext()
            editingReplacement = nil
            loadData()
        } catch {
            errorMessage = localized("Failed to update replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func saveVocabularyEdit(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        let trimmed = editPrimaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingVocabulary = nil
            return
        }
        let isDuplicate = vocabularyWords.contains {
            $0.id != word.id && $0.word.lowercased() == trimmed.lowercased()
        }
        guard !isDuplicate else {
            editingVocabulary = nil
            return
        }
        do {
            word.word = trimmed
            try store.saveContext()
            editingVocabulary = nil
            loadData()
        } catch {
            errorMessage = localized("Failed to update word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func setMatchMode(_ replacement: WordReplacement, mode: ReplacementMatchMode) {
        guard let store = dictionaryStore else { return }
        do {
            replacement.matchModeRawValue = mode.rawValue
            try store.saveContext()
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveReplacements(from source: IndexSet, to destination: Int) {
        guard let store = dictionaryStore else { return }
        do {
            try store.reorder(orderedReplacements, from: source, to: destination)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteReplacement(_ replacement: WordReplacement) {
        guard let store = dictionaryStore else { return }
        do {
            try store.delete(replacement)
            if selectedRowID == replacement.id { selectedRowID = nil }
            loadData()
        } catch {
            errorMessage = localized("Failed to delete replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func deleteVocabularyWord(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        do {
            try store.delete(word)
            if selectedRowID == word.id { selectedRowID = nil }
            loadData()
        } catch {
            errorMessage = localized("Failed to delete word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func loadData() {
        guard let store = dictionaryStore else { return }
        do {
            replacements = try store.fetchAllReplacements()
            vocabularyWords = try store.fetchAllVocabularyWords()
        } catch {
            errorMessage = localized("Failed to load data: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to export dictionary: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
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
                errorMessage = localized("Failed to read import file: %@", locale: locale)
                    .replacingOccurrences(of: "%@", with: error.localizedDescription)
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
            errorMessage = localized("Failed to import dictionary: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.shouldHandleListKeyEvent(event) else { return event }
            if self.editingReplacement != nil || self.editingVocabulary != nil
                || self.showAddWordSheet || self.showAddReplacementSheet {
                return event
            }
            return self.handleListKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static func shouldHandleListKeyEvent(_ event: NSEvent) -> Bool {
        guard MainWindowController.isMainWindowKey(event.window) else { return false }
        if isTextInputFirstResponder(event.window?.firstResponder) {
            return false
        }
        return true
    }

    private static func isTextInputFirstResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSTextField { return true }
        if let textView = responder as? NSTextView {
            return textView.isEditable || textView.isSelectable
        }
        if responder is NSText { return true }
        return false
    }

    private func handleListKeyEvent(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 126:
            moveSelection(delta: -1)
            return nil
        case 125:
            moveSelection(delta: 1)
            return nil
        case 51, 117:
            deleteSelectedRow()
            return nil
        case 53:
            if selectedRowID != nil {
                selectedRowID = nil
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func moveSelection(delta: Int) {
        let ids = orderedSelectableIDs
        let currentIndex = ids.firstIndex(where: { $0 == selectedRowID })
        guard let nextIndex = ListSelectionNavigation.moveIndex(
            current: currentIndex,
            count: ids.count,
            delta: delta
        ) else { return }
        selectedRowID = ids[nextIndex]
    }

    private func deleteSelectedRow() {
        guard let selectedRowID else { return }
        if let replacement = replacements.first(where: { $0.id == selectedRowID }) {
            deleteReplacement(replacement)
            self.selectedRowID = nil
        } else if let word = vocabularyWords.first(where: { $0.id == selectedRowID }) {
            deleteVocabularyWord(word)
            self.selectedRowID = nil
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
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
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
