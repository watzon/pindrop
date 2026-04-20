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

    @State private var hoveredRowID: UUID?

    private var builtInPresets: [PromptPreset] {
        presets.filter { $0.isBuiltIn }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private var customPresets: [PromptPreset] {
        presets.filter { !$0.isBuiltIn }.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {

                    if isCreating {
                        createForm
                    } else {
                        createButton
                    }

                    if !builtInPresets.isEmpty {
                        builtInSection
                    }

                    customSection
                }
                .padding(AppTheme.Spacing.xl)
            }
        }
        .frame(width: 600, height: 700)
        .background(AppColors.windowBackground)
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
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            HStack(spacing: AppTheme.Spacing.xs) {
                Button(action: handleImport) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help(localized("Import Presets", locale: locale))

                Button(action: handleExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help(localized("Export Presets", locale: locale))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.surfaceBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(AppColors.divider),
            alignment: .bottom
        )
    }

    // MARK: - Create Section

    private var createButton: some View {
        Button {
            withAnimation(AppTheme.Animation.fast) {
                isCreating = true
                newName = ""
                newPrompt = ""
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))

                Text(localized("Create New Preset", locale: locale))
                    .font(AppTypography.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppColors.accent.opacity(0.1))
            )
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md),
                style: AppColors.accent.opacity(0.3)
            )
            .foregroundStyle(AppColors.accent)
        }
        .buttonStyle(.plain)
    }

    private var createForm: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text(localized("New Preset", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(localized("Preset Name", locale: locale), text: $newName)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .aiSettingsInputChrome()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(localized("Prompt", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                TextEditor(text: $newPrompt)
                    .font(AppTypography.body)
                    .frame(height: 100)
                    .padding(4)
                    .background(AppColors.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .hairlineBorder(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm),
                        style: AppColors.border
                    )

                Text(localized("Use ${transcription} as a placeholder for the transcribed text.", locale: locale))
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                Button(localized("Cancel", locale: locale)) {
                    withAnimation(AppTheme.Animation.fast) {
                        isCreating = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Button(localized("Create", locale: locale)) {
                    saveNewPreset()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                .disabled(newName.isEmpty || newPrompt.isEmpty)
                .opacity(newName.isEmpty || newPrompt.isEmpty ? 0.5 : 1)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
            style: AppColors.border
        )
    }

    // MARK: - Built-in Section

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(localized("Built-in Presets", locale: locale))
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.xs)

            VStack(spacing: 0) {
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
                    .background(
                        hoveredRowID == preset.id ? AppColors.surfaceBackground : Color.clear
                    )
                    .onHover { isHovered in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredRowID = isHovered ? preset.id : nil
                        }
                    }

                    if preset.id != builtInPresets.last?.id {
                        Divider().background(AppColors.divider)
                    }
                }
            }
            .background(AppColors.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
                style: AppColors.border
            )
        }
    }

    // MARK: - Custom Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(localized("Custom Presets", locale: locale))
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.xs)

            if customPresets.isEmpty {
                emptyCustomState
            } else {
                VStack(spacing: 0) {
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
                        .background(
                            hoveredRowID == preset.id ? AppColors.surfaceBackground : Color.clear
                        )
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredRowID = isHovered ? preset.id : nil
                            }
                        }

                        if preset.id != customPresets.last?.id {
                            Divider().background(AppColors.divider)
                        }
                    }
                }
                .background(AppColors.contentBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                .hairlineBorder(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
                    style: AppColors.border
                )
            }
        }
    }

    private var emptyCustomState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "text.quote")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("No Custom Presets", locale: locale))
                .font(AppTypography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)

            Text(localized("Create your own presets or duplicate built-in ones to customize them.", locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(AppColors.surfaceBackground.opacity(0.5))
        )
        .hairlineBorder(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg),
            style: AppColors.border,
            dash: [5]
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
            withAnimation(AppTheme.Animation.fast) {
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

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editingView
            } else {
                displayView
            }
        }
        .padding(AppTheme.Spacing.md)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var displayView: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: preset.isBuiltIn ? "lock.fill" : "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(preset.isBuiltIn ? AppColors.textTertiary : AppColors.accent)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(preset.isBuiltIn ? AppColors.surfaceBackground : AppColors.accent.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.textPrimary)

                Text(preset.prompt)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: AppTheme.Spacing.xs) {
                if !preset.isBuiltIn {
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
                    .help(localized("Edit Preset", locale: locale))
                }

                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? AppColors.elevatedSurface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                .opacity(isHovered ? 1 : 0)
                .help(localized("Duplicate Preset", locale: locale))

                if !preset.isBuiltIn {
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
                    .help(localized("Delete Preset", locale: locale))
                }
            }
        }
    }

    private var editingView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            TextField(localized("Preset Name", locale: locale), text: $editName)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .aiSettingsInputChrome()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                TextEditor(text: $editPrompt)
                    .font(AppTypography.body)
                    .frame(height: 80)
                    .padding(4)
                    .background(AppColors.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .hairlineBorder(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm),
                        style: AppColors.border
                    )

                Text(localized("Use ${transcription} as placeholder", locale: locale))
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }

            HStack {
                Spacer()

                Button(action: onCancelEdit) {
                    Text(localized("Cancel", locale: locale))
                        .font(AppTypography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 8)

                Button(action: onSaveEdit) {
                    Text(localized("Save", locale: locale))
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.accent.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}
