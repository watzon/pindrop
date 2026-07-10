//
//  NotesView.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import SwiftData
import Foundation
import AppKit

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @Query(sort: \NoteSchema.Note.updatedAt, order: .reverse) private var allNotes: [NoteSchema.Note]

    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedNoteID: PersistentIdentifier?
    @State private var pendingDeletionNote: NoteSchema.Note?
    @State private var errorMessage: String?
    @State private var keyMonitor: Any?

    private var notesStore: NotesStore {
        NotesStore(modelContext: modelContext)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredNotes: [NoteSchema.Note] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return allNotes }
        return allNotes.filter { note in
            note.title.localizedStandardContains(query)
                || note.content.localizedStandardContains(query)
        }
    }

    private var flatSelectableNotes: [NoteSchema.Note] {
        groupedNotes.flatMap(\.notes)
    }

    private var groupedNotes: [(key: NotesGrouping.SectionKey, notes: [NoteSchema.Note])] {
        let inputs = filteredNotes.map {
            NotesGrouping.Input(id: $0.id, updatedAt: $0.updatedAt, isPinned: $0.isPinned)
        }
        let byID = Dictionary(uniqueKeysWithValues: filteredNotes.map { ($0.id, $0) })
        return NotesGrouping.sections(notes: inputs).compactMap { section in
            let notes = section.ids.compactMap { byID[$0] }
            guard !notes.isEmpty else { return nil }
            return (key: section.key, notes: notes)
        }
    }

    private var headerSubtitleText: String {
        let count = filteredNotes.count
        return count == 1
            ? localized("1 note", locale: locale)
            : "\(count) \(localized("notes", locale: locale))"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.bottom, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .background(AppColors.contentBackground)

            contentArea
                .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
        .confirmationDialog(
            localized("Delete note?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionNote != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletionNote = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                if let note = pendingDeletionNote {
                    deleteNote(note)
                }
                pendingDeletionNote = nil
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                pendingDeletionNote = nil
            }
        } message: {
            Text(localized("This will permanently remove this note.", locale: locale))
        }
        .onAppear { installKeyMonitorIfNeeded() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(localized("Notes", locale: locale))
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(headerSubtitleText)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: AppTheme.Spacing.lg)

                Button(action: createNewNote) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(localized("New Note", locale: locale))
                            .font(AppTypography.subheadline)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .controlSize(.regular)
            }

            searchBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)

            TextField(localized("Search notes...", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous),
            style: AppColors.border
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if filteredNotes.isEmpty {
            emptyStateView
        } else {
            notesList
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
            Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text(searchText.isEmpty
                 ? localized("No notes yet", locale: locale)
                 : localized("No results found", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text(searchText.isEmpty
                 ? localized("Create your first note to get started", locale: locale)
                 : localized("Try a different search term", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            if searchText.isEmpty {
                Button(localized("Create New Note", locale: locale)) {
                    createNewNote()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .padding(.top, AppTheme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(groupedNotes, id: \.key) { group in
                    dateHeader(localizedSectionTitle(group.key))
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xs)

                    ForEach(group.notes) { note in
                        NoteHistoryRow(
                            note: note,
                            isSelected: selectedNoteID == note.persistentModelID,
                            onTap: {
                                selectedNoteID = note.persistentModelID
                                openNote(note)
                            },
                            onDelete: { pendingDeletionNote = note },
                            onTogglePin: { togglePin(note) }
                        )
                    }
                }

                Color.clear.frame(height: AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
        }
    }

    private func dateHeader(_ title: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
        }
    }

    private func localizedSectionTitle(_ key: NotesGrouping.SectionKey) -> String {
        localized(key.localizationKey, locale: locale)
    }

    // MARK: - Actions

    private func createNewNote() {
        let editorController = NoteEditorWindowController()
        editorController.setModelContainer(modelContext.container)
        editorController.show(note: nil, isNewNote: true)
    }

    private func openNote(_ note: NoteSchema.Note) {
        selectedNoteID = note.persistentModelID
        let editorController = NoteEditorWindowController()
        editorController.setModelContainer(modelContext.container)
        editorController.show(note: note, isNewNote: false)
    }

    private func togglePin(_ note: NoteSchema.Note) {
        do {
            try notesStore.togglePin(note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ note: NoteSchema.Note) {
        do {
            try notesStore.delete(note)
            if selectedNoteID == note.persistentModelID {
                selectedNoteID = nil
            }
        } catch {
            errorMessage = localized("Failed to delete note: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    // MARK: - Keyboard Selection

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard shouldHandleListKeyEvent(event) else { return event }
            return handleListKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shouldHandleListKeyEvent(_ event: NSEvent) -> Bool {
        guard MainWindowController.isMainWindowKey(event.window) else { return false }
        if isSearchFieldFocused { return false }
        if Self.isTextInputFirstResponder(event.window?.firstResponder) {
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
            moveListSelection(delta: -1)
            return nil
        case 125:
            moveListSelection(delta: 1)
            return nil
        case 51, 117:
            requestDeleteForSelection()
            return nil
        case 53:
            return clearSelection() ? nil : event
        default:
            return event
        }
    }

    private func moveListSelection(delta: Int) {
        let notes = flatSelectableNotes
        let currentIndex = notes.firstIndex(where: { $0.persistentModelID == selectedNoteID })
        guard let nextIndex = ListSelectionNavigation.moveIndex(
            current: currentIndex,
            count: notes.count,
            delta: delta
        ) else { return }
        selectedNoteID = notes[nextIndex].persistentModelID
    }

    private func requestDeleteForSelection() {
        if let note = flatSelectableNotes.first(where: { $0.persistentModelID == selectedNoteID }) {
            pendingDeletionNote = note
        }
    }

    @discardableResult
    private func clearSelection() -> Bool {
        guard selectedNoteID != nil else { return false }
        selectedNoteID = nil
        return true
    }
}

// MARK: - Preview

#Preview("Notes View - With Data") {
    NotesView()
        .modelContainer(PreviewContainer.withSampleNotes)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.light)
}

#Preview("Notes View - Empty") {
    NotesView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.light)
}

#Preview("Notes View - Dark") {
    NotesView()
        .modelContainer(PreviewContainer.withSampleNotes)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}
