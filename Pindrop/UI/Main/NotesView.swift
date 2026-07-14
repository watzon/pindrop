//
//  NotesView.swift
//  Pindrop
//
//  Created on 2026-01-29.
//
//  Notes page (U5 scorched-earth restyle, spec §10).
//

import SwiftUI
import SwiftData
import Foundation
import AppKit

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @Query(sort: \NoteSchema.Note.updatedAt, order: .reverse) private var allNotes: [NoteSchema.Note]

    /// Applied search query driving the derived list snapshot.
    /// Empty clears immediately; non-empty queries debounce before applying.
    @State private var appliedSearchQuery = ""
    /// Draft empty/nonempty intent for empty-state wording only. Updates on
    /// whitespace-empty transitions so presentation is immediate while the
    /// expensive filter query remains debounced.
    @State private var hasDraftSearchIntent = false
    @State private var snapshotCache = NotesListSnapshotCache()
    /// Focus stays on the list owner so keyboard selection can exclude the field;
    /// draft text/debounce live in `NotesSearchChrome`.
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedNoteID: PersistentIdentifier?
    @State private var pendingDeletionNote: NoteSchema.Note?
    @State private var errorMessage: String?
    @State private var keyMonitor: Any?

    private var notesStore: NotesStore {
        NotesStore(modelContext: modelContext)
    }

    /// Single derived snapshot for body + keyboard selection (one derivation per input change).
    private func listSnapshot() -> NotesListSnapshot {
        snapshotCache.snapshot(notes: allNotes, query: appliedSearchQuery)
    }

    var body: some View {
        // Exactly one snapshot/fingerprint evaluation per owner body.
        let snapshot = listSnapshot()
        VStack(spacing: 0) {
            headerSection(filteredCount: snapshot.filteredCount)
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            contentArea(snapshot: snapshot)
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
        .onAppear {
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .background {
            // ⌘N new note (hidden button for keyboard shortcut)
            Button(action: createNewNote) { EmptyView() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Header

    private func headerSection(filteredCount: Int) -> some View {
        PageHeader(
            title: localized("Notes", locale: locale),
            meta: NotesHeaderMeta.text(noteCount: filteredCount, locale: locale)
        ) {
            HStack(spacing: 10) {
                NotesSearchChrome(
                    placeholder: localized("Search notes...", locale: locale),
                    isFocused: $isSearchFieldFocused,
                    onAppliedQueryChange: { query in
                        appliedSearchQuery = query
                    },
                    onDraftSearchIntentChange: { hasIntent in
                        hasDraftSearchIntent = hasIntent
                    }
                )
                .frame(width: 200)

                PrimaryButton(
                    title: localized("New note", locale: locale),
                    systemImage: "plus",
                    keyboardHint: "⌘N",
                    action: createNewNote
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentArea(snapshot: NotesListSnapshot) -> some View {
        if let errorMessage {
            errorView(errorMessage)
        } else if snapshot.filteredCount == 0 {
            emptyStateView(isSearching: hasDraftSearchIntent)
        } else {
            notesList(snapshot: snapshot)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("Something went wrong", locale: locale))
                .font(AppTypography.labelStrong)
                .foregroundStyle(AppColors.textPrimary)

            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            SecondaryButton(title: localized("Dismiss", locale: locale)) {
                self.errorMessage = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateView(isSearching: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "note.text")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(isSearching
                 ? localized("No results found", locale: locale)
                 : localized("No notes yet", locale: locale))
                .font(AppTypography.labelStrong)
                .foregroundStyle(AppColors.textPrimary)

            Text(isSearching
                 ? localized("Try a different search term", locale: locale)
                 : localized("Create your first note to get started", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            if !isSearching {
                PrimaryButton(
                    title: localized("New note", locale: locale),
                    systemImage: "plus",
                    action: createNewNote
                )
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notesList(snapshot: NotesListSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.sections.enumerated()), id: \.element.key) { index, group in
                    SectionHeader(
                        title: localizedSectionTitle(group.key),
                        trailing: "\(group.notes.count)",
                        isFirst: index == 0
                    )
                    .padding(.horizontal, 20)

                    if group.key == .pinned {
                        ForEach(group.notes) { note in
                            pinnedCard(note)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                    } else {
                        ForEach(group.notes) { note in
                            noteRow(note)
                        }
                    }
                }

                Color.clear.frame(height: 32)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Pinned card (spec §10)

    private func pinnedCard(_ note: NoteSchema.Note) -> some View {
        let isSelected = selectedNoteID == note.persistentModelID
        let title = NotesListPresentation.displayTitle(
            title: note.title,
            content: note.content,
            emptyTitle: localized("Untitled Note", locale: locale)
        )
        let preview = NotesListPresentation.previewLine(content: note.content)
        let edited = NotesDateFormatting.editedLabel(
            date: note.updatedAt,
            locale: locale
        )

        return Button {
            selectedNoteID = note.persistentModelID
            openNote(note)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(AppTypography.pinnedCardTitle)
                        .lineSpacing(AppTypography.pinnedCardTitleLineSpacing)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.accent)

                    Text(edited)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }

                if !preview.isEmpty {
                    Text(preview)
                        .font(AppTypography.body)
                        .lineSpacing(4) // ~13/20
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.accent.opacity(0.5) : AppColors.border,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { noteContextMenu(note) }
    }

    // MARK: - Note row (spec §10)

    private func noteRow(_ note: NoteSchema.Note) -> some View {
        let isSelected = selectedNoteID == note.persistentModelID
        let title = NotesListPresentation.displayTitle(
            title: note.title,
            content: note.content,
            emptyTitle: localized("Untitled Note", locale: locale)
        )
        let preview = NotesListPresentation.previewLine(content: note.content)
        let dateText = NotesDateFormatting.rowDate(
            date: note.updatedAt,
            locale: locale
        )

        return Button {
            selectedNoteID = note.persistentModelID
            openNote(note)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)

                Text(preview)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(dateText)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88, alignment: .trailing)
            }
            .padding(.vertical, 13)
            // Divider inside the horizontal padding: constrained to the content
            // column; the selected wash below stays full-bleed.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .background(isSelected ? AppColors.accent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { noteContextMenu(note) }
    }

    @ViewBuilder
    private func noteContextMenu(_ note: NoteSchema.Note) -> some View {
        Button {
            openNote(note)
        } label: {
            Label(localized("Open Note", locale: locale), systemImage: "square.and.pencil")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.content, forType: .string)
        } label: {
            Label(localized("Copy Content", locale: locale), systemImage: "doc.on.doc")
        }

        Button {
            togglePin(note)
        } label: {
            Label(
                note.isPinned ? localized("Unpin", locale: locale) : localized("Pin", locale: locale),
                systemImage: note.isPinned ? "pin.slash" : "pin"
            )
        }

        Divider()

        Button(role: .destructive) {
            pendingDeletionNote = note
        } label: {
            Label(localized("Delete Note", locale: locale), systemImage: "trash")
        }
    }

    private func localizedSectionTitle(_ key: NotesGrouping.SectionKey) -> String {
        localized(key.localizationKey, locale: locale)
    }

    // MARK: - Actions

    private func createNewNote() {
        presentNoteEditor(note: nil, isNewNote: true)
    }

    private func openNote(_ note: NoteSchema.Note) {
        selectedNoteID = note.persistentModelID
        presentNoteEditor(note: note, isNewNote: false)
    }

    private func presentNoteEditor(note: NoteSchema.Note?, isNewNote: Bool) {
        let editorController = NoteEditorWindowController()
        let registry = NoteEditorWindowControllerRegistry.shared
        editorController.setModelContainer(modelContext.container)
        registry.retain(editorController)
        editorController.onClose = { [weak registry, weak editorController] in
            guard let editorController else { return }
            registry?.release(editorController)
        }
        editorController.show(note: note, isNewNote: isNewNote)
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
        let selectable = listSnapshot().flatSelectableNotes
        switch event.keyCode {
        case 126:
            moveListSelection(delta: -1, notes: selectable)
            return nil
        case 125:
            moveListSelection(delta: 1, notes: selectable)
            return nil
        case 51, 117:
            requestDeleteForSelection(notes: selectable)
            return nil
        case 53:
            return clearSelection() ? nil : event
        case 36: // Return
            if let note = selectable.first(where: { $0.persistentModelID == selectedNoteID }) {
                openNote(note)
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func moveListSelection(delta: Int, notes: [NoteSchema.Note]) {
        let currentIndex = notes.firstIndex(where: { $0.persistentModelID == selectedNoteID })
        guard let nextIndex = ListSelectionNavigation.moveIndex(
            current: currentIndex,
            count: notes.count,
            delta: delta
        ) else { return }
        selectedNoteID = notes[nextIndex].persistentModelID
    }

    private func requestDeleteForSelection(notes: [NoteSchema.Note]) {
        if let note = notes.first(where: { $0.persistentModelID == selectedNoteID }) {
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

// MARK: - Search draft intent

/// Pure helpers for notes search draft intent (empty-state wording).
/// Filtering still uses the debounced applied query; only the empty/nonempty
/// boundary is published upward for immediate empty-state presentation.
enum NotesSearchPresentation {
    /// True when the draft has any non-whitespace content.
    static func hasDraftSearchIntent(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the new intent only when the empty/nonempty boundary is crossed;
    /// `nil` means the owner should not be notified (no keystroke fan-out).
    static func draftSearchIntentTransition(
        previousHasIntent: Bool,
        draft: String
    ) -> Bool? {
        let next = hasDraftSearchIntent(draft)
        return next == previousHasIntent ? nil : next
    }
}

// MARK: - Search chrome (draft state isolated)

/// Owns draft search text and the 250 ms debounce so keystrokes do not
/// invalidate the list-owning `NotesView` body. Empty clears apply immediately;
/// non-empty queries settle after 250 ms. Draft empty/nonempty intent is
/// published immediately (boolean only) for empty-state presentation.
private struct NotesSearchChrome: View {
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding
    let onAppliedQueryChange: (String) -> Void
    let onDraftSearchIntentChange: (Bool) -> Void

    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var lastPublishedDraftIntent = false

    var body: some View {
        SearchFieldChrome(
            text: $searchText,
            placeholder: placeholder,
            showsKeyboardHint: true,
            isFocused: isFocused
        )
        .onChange(of: searchText) { _, _ in
            handleSearchTextChange()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleSearchTextChange() {
        let query = trimmedSearchText
        publishDraftSearchIntentIfNeeded(for: searchText)
        if query.isEmpty {
            // Empty query must clear results immediately (no debounce lag).
            applySearchQueryImmediately("")
            return
        }
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            // Re-read current field so a superseded keystroke is ignored.
            let latest = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            onAppliedQueryChange(latest)
        }
    }

    private func applySearchQueryImmediately(_ query: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        onAppliedQueryChange(query)
    }

    private func publishDraftSearchIntentIfNeeded(for draft: String) {
        guard let next = NotesSearchPresentation.draftSearchIntentTransition(
            previousHasIntent: lastPublishedDraftIntent,
            draft: draft
        ) else {
            return
        }
        lastPublishedDraftIntent = next
        onDraftSearchIntentChange(next)
    }
}

// MARK: - Derived list snapshot

/// One-shot derived Notes list: filtered count, grouped sections, flat selection order.
private struct NotesListSnapshot {
    struct Section {
        let key: NotesGrouping.SectionKey
        let notes: [NoteSchema.Note]
    }

    let filteredCount: Int
    let sections: [Section]
    let flatSelectableNotes: [NoteSchema.Note]

    static let empty = NotesListSnapshot(
        filteredCount: 0,
        sections: [],
        flatSelectableNotes: []
    )
}

/// Identity fingerprint for note list inputs (avoids full-content re-derivation on unrelated body ticks).
/// Searchable text is included while a query is active: edit timestamps are not
/// unique, so two content saves can legitimately share the same `updatedAt` value.
private struct NotesListInputFingerprint: Equatable {
    struct NoteIdentity: Equatable {
        let id: UUID
        let updatedAt: Date
        let isPinned: Bool
        let searchableTitle: String?
        let searchableContent: String?
    }

    let query: String
    let notes: [NoteIdentity]
}

/// Class init stays nonisolated for `@State` default construction under Swift 5.9;
/// mutation is method-isolated (`@MainActor` accessors only).
private final class NotesListSnapshotCache {
    private var fingerprint: NotesListInputFingerprint?
    private var value: NotesListSnapshot = .empty

    @MainActor
    func snapshot(notes: [NoteSchema.Note], query: String) -> NotesListSnapshot {
        let isSearching = !query.isEmpty
        let nextFingerprint = NotesListInputFingerprint(
            query: query,
            notes: notes.map {
                NotesListInputFingerprint.NoteIdentity(
                    id: $0.id,
                    updatedAt: $0.updatedAt,
                    isPinned: $0.isPinned,
                    searchableTitle: isSearching ? $0.title : nil,
                    searchableContent: isSearching ? $0.content : nil
                )
            }
        )
        if fingerprint == nextFingerprint {
            return value
        }
        fingerprint = nextFingerprint
        value = Self.derive(notes: notes, query: query)
        return value
    }

    @MainActor
    private static func derive(notes: [NoteSchema.Note], query: String) -> NotesListSnapshot {
        let filtered: [NoteSchema.Note]
        if query.isEmpty {
            filtered = notes
        } else {
            filtered = notes.filter { note in
                note.title.localizedStandardContains(query)
                    || note.content.localizedStandardContains(query)
            }
        }

        let inputs = filtered.map {
            NotesGrouping.Input(id: $0.id, updatedAt: $0.updatedAt, isPinned: $0.isPinned)
        }
        let byID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        let sections: [NotesListSnapshot.Section] = NotesGrouping.sections(notes: inputs).compactMap { section in
            let sectionNotes = section.ids.compactMap { byID[$0] }
            guard !sectionNotes.isEmpty else { return nil }
            return NotesListSnapshot.Section(key: section.key, notes: sectionNotes)
        }
        let flat = sections.flatMap(\.notes)
        return NotesListSnapshot(
            filteredCount: filtered.count,
            sections: sections,
            flatSelectableNotes: flat
        )
    }
}

@MainActor
final class NoteEditorWindowControllerRegistry {
    static let shared = NoteEditorWindowControllerRegistry()

    private var controllers: [NoteEditorWindowController] = []

    var count: Int { controllers.count }

    func retain(_ controller: NoteEditorWindowController) {
        controllers.append(controller)
    }

    func release(_ controller: NoteEditorWindowController) {
        controllers.removeAll { $0 === controller }
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
