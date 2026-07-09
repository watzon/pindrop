//
//  PresetManagementSheet.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import SwiftUI
import SwiftData

struct PresetManagementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var store: PromptPresetStore?
    @State private var presets: [PromptPreset] = []

    @State private var isCreating = false
    @State private var newName = ""
    @State private var newPrompt = ""

    @State private var editingPresetID: UUID?
    @State private var editName = ""
    @State private var editPrompt = ""

    @State private var errorMessage: String?
    @State private var presetToDelete: PromptPreset?
    @State private var showDeleteConfirmation = false
    @State private var showingImportStrategyDialog = false
    @State private var importDataCache: Data?

    private var builtInPresets: [PromptPreset] {
        presets.filter { $0.isBuiltIn }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var customPresets: [PromptPreset] {
        presets.filter { !$0.isBuiltIn }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section(localized("Create Preset", locale: locale)) {
                    if isCreating {
                        createForm
                    } else {
                        createButton
                    }
                }

                if !builtInPresets.isEmpty {
                    builtInSection
                }

                customSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 700)
        .onAppear {
            store = PromptPresetStore(modelContext: modelContext)
            loadData()
        }
        .alert(localized("Error", locale: locale), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(localized("OK", locale: locale)) { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .confirmationDialog(localized("Delete Preset?", locale: locale), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                if let preset = presetToDelete {
                    deletePreset(preset)
                }
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                presetToDelete = nil
            }
        } message: {
            if let preset = presetToDelete {
                Text(localized("Are you sure you want to delete '%@'? This action cannot be undone.", locale: locale).replacingOccurrences(of: "%@", with: preset.name))
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
            Text(localized("Choose how to import the preset data", locale: locale))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(localized("Manage Presets", locale: locale))
                .font(.headline)

            Spacer()

            HStack {
                Button(localized("Import", locale: locale), systemImage: "square.and.arrow.down", action: handleImport)
                    .help(localized("Import Presets", locale: locale))

                Button(localized("Export", locale: locale), systemImage: "square.and.arrow.up", action: handleExport)
                    .help(localized("Export Presets", locale: locale))
            }
            .labelStyle(.iconOnly)

            Button(localized("Done", locale: locale)) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Create Section

    private var createButton: some View {
        Button {
            withAnimation {
                isCreating = true
                newName = ""
                newPrompt = ""
            }
        } label: {
            Label(localized("Create New Preset", locale: locale), systemImage: "plus")
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(localized("Preset Name", locale: locale), text: $newName)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Prompt", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $newPrompt)
                    .frame(height: 100)

                Text(localized("Use ${transcription} as a placeholder for the transcribed text.", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(localized("Cancel", locale: locale)) {
                    withAnimation {
                        isCreating = false
                    }
                }

                Spacer()

                Button(localized("Create", locale: locale)) {
                    saveNewPreset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newPrompt.isEmpty)
            }
        }
    }

    // MARK: - Built-in Section

    private var builtInSection: some View {
        Section(localized("Built-in Presets", locale: locale)) {
            ForEach(builtInPresets) { preset in
                PresetRow(
                    preset: preset,
                    isEditing: false,
                    editName: .constant(""),
                    editPrompt: .constant(""),
                    onStartEdit: {},
                    onSaveEdit: {},
                    onCancelEdit: {},
                    onDelete: {},
                    onDuplicate: { duplicatePreset(preset) }
                )
            }
        }
    }

    // MARK: - Custom Section

    private var customSection: some View {
        Section(localized("Custom Presets", locale: locale)) {
            if customPresets.isEmpty {
                emptyCustomState
            } else {
                ForEach(customPresets) { preset in
                    PresetRow(
                        preset: preset,
                        isEditing: editingPresetID == preset.id,
                        editName: $editName,
                        editPrompt: $editPrompt,
                        onStartEdit: { startEditing(preset) },
                        onSaveEdit: { saveEdit(preset) },
                        onCancelEdit: { cancelEditing() },
                        onDelete: {
                            presetToDelete = preset
                            showDeleteConfirmation = true
                        },
                        onDuplicate: { duplicatePreset(preset) }
                    )
                }
            }
        }
    }

    private var emptyCustomState: some View {
        ContentUnavailableView(
            localized("No Custom Presets", locale: locale),
            systemImage: "text.quote",
            description: Text(
                localized("Create your own presets or duplicate built-in ones to customize them.", locale: locale)
            )
        )
    }

    // MARK: - Actions

    private func loadData() {
        guard let store = store else { return }
        do {
            presets = try store.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveNewPreset() {
        guard let store = store else { return }

        let preset = PromptPreset(
            name: newName,
            prompt: newPrompt,
            isBuiltIn: false,
            sortOrder: presets.count
        )

        do {
            try store.add(preset)
            loadData()
            withAnimation {
                isCreating = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startEditing(_ preset: PromptPreset) {
        editingPresetID = preset.id
        editName = preset.name
        editPrompt = preset.prompt
    }

    private func saveEdit(_ preset: PromptPreset) {
        guard let store = store else { return }

        preset.name = editName
        preset.prompt = editPrompt

        do {
            try store.update(preset)
            loadData()
            cancelEditing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelEditing() {
        editingPresetID = nil
        editName = ""
        editPrompt = ""
    }

    private func deletePreset(_ preset: PromptPreset) {
        guard let store = store else { return }

        do {
            try store.delete(preset)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicatePreset(_ preset: PromptPreset) {
        guard let store = store else { return }

        do {
            _ = try store.duplicate(preset)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export/Import

    private func handleExport() {
        guard let store = store else { return }

        do {
            let jsonData = try store.exportToJSON()

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "presets.json"
            let currentLocale = locale
            savePanel.title = localized("Export Presets", locale: currentLocale)
            savePanel.message = localized("Choose a location to save the presets", locale: currentLocale)

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
            }
        } catch {
            errorMessage = localized("Failed to export presets: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func handleImport() {
        let openPanel = NSOpenPanel()
        let currentLocale = locale
        openPanel.allowedContentTypes = [.json]
        openPanel.title = localized("Import Presets", locale: currentLocale)
        openPanel.message = localized("Select a presets JSON file to import", locale: currentLocale)

        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                showingImportStrategyDialog = true
                importDataCache = data
            } catch {
                errorMessage = localized("Failed to read import file: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
            }
        }
    }

    private func performImport(strategy: PromptPresetStore.ImportStrategy) {
        guard let store = store, let data = importDataCache else { return }

        do {
            try store.importFromJSON(data, strategy: strategy)
            loadData()
            importDataCache = nil
        } catch {
            errorMessage = localized("Failed to import presets: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    @Environment(\.locale) private var locale

    let preset: PromptPreset
    let isEditing: Bool
    @Binding var editName: String
    @Binding var editPrompt: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        if isEditing {
            editingView
        } else {
            displayView
        }
    }

    private var displayView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preset.isBuiltIn ? "lock.fill" : "person.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .fontWeight(.medium)

                Text(preset.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack {
                if !preset.isBuiltIn {
                    Button(localized("Edit Preset", locale: locale), systemImage: "pencil", action: onStartEdit)
                        .help(localized("Edit Preset", locale: locale))
                }

                Button(
                    localized("Duplicate Preset", locale: locale),
                    systemImage: "doc.on.doc",
                    action: onDuplicate
                )
                .help(localized("Duplicate Preset", locale: locale))

                if !preset.isBuiltIn {
                    Button(
                        localized("Delete Preset", locale: locale),
                        systemImage: "trash",
                        role: .destructive,
                        action: onDelete
                    )
                        .help(localized("Delete Preset", locale: locale))
                }
            }
            .labelStyle(.iconOnly)
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(localized("Preset Name", locale: locale), text: $editName)

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $editPrompt)
                    .frame(height: 80)

                Text(localized("Use ${transcription} as placeholder", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button(localized("Cancel", locale: locale), action: onCancelEdit)

                Button(localized("Save", locale: locale), action: onSaveEdit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
