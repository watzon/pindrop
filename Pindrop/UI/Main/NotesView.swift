//
//  NotesView.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import SwiftData
import Foundation

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    
    @Query(sort: \NoteSchema.Note.updatedAt, order: .reverse) private var notes: [NoteSchema.Note]
    
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .descending
    @State private var selectedNote: NoteSchema.Note?
    @State private var errorMessage: String?
    
    private var notesStore: NotesStore {
        NotesStore(modelContext: modelContext)
    }
    
    private var filteredNotes: [NoteSchema.Note] {
        let sorted = sortNotes(notes)
        
        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { note in
                note.title.localizedStandardContains(searchText) ||
                note.content.localizedStandardContains(searchText) ||
                note.tags.contains { $0.localizedStandardContains(searchText) }
            }
        }
    }
    
    private func sortNotes(_ notes: [NoteSchema.Note]) -> [NoteSchema.Note] {
        switch sortOrder {
        case .ascending:
            return notes.sorted { $0.updatedAt < $1.updatedAt }
        case .descending:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    // Grid columns - adaptive with minimum 250px width
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250), spacing: AppTheme.Spacing.md)]
    }
    
    var body: some View {
        MainContentPageLayout(scrollContent: false, headerBottomPadding: AppTheme.Spacing.lg) {
            fixedHeader
        } content: {
            VStack(spacing: AppTheme.Spacing.lg) {
                searchBar
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
    
    // MARK: - Header
    
    private var fixedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(localized("Notes", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("\(filteredNotes.count) \(localized("notes", locale: locale))")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            Button(action: toggleSortOrder) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: sortOrder == .ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 12))
                    Text("\(localized("Date", locale: locale)) \(sortOrder == .ascending ? "↑" : "↓")")
                        .font(AppTypography.subheadline)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.borderless)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppColors.surfaceBackground)
            )
            .hairlineStroke(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous),
                style: AppColors.border
            )
            .help(localized("Toggle sort order", locale: locale))
            
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
    }
    
    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            
            TextField(localized("Search notes...", locale: locale), text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
            
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
        if let errorMessage = errorMessage {
            errorView(errorMessage)
        } else if filteredNotes.isEmpty {
            emptyStateView
        } else {
            notesGrid
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
    
    private var notesGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.md) {
                ForEach(filteredNotes) { note in
                    NoteCardView(
                        note: note,
                        isSelected: selectedNote?.id == note.id,
                        onOpen: { openNote(note) },
                        onDelete: { deleteNote(note) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Actions
    
    private func toggleSortOrder() {
        withAnimation(AppTheme.Animation.fast) {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        }
    }
    
    private func createNewNote() {
        let editorController = NoteEditorWindowController()
        editorController.setModelContainer(modelContext.container)
        editorController.show(note: nil, isNewNote: true)
        
        editorController.onClose = {
        }
        
        editorController.onSave = { _ in
        }
    }
    
    private func openNote(_ note: NoteSchema.Note) {
        selectedNote = note
        
        let editorController = NoteEditorWindowController()
        editorController.setModelContainer(modelContext.container)
        editorController.show(note: note, isNewNote: false)
        
        editorController.onClose = { [weak note] in
            if note == nil {
                selectedNote = nil
            }
        }
        
        editorController.onSave = { _ in
        }
    }
    
    private func deleteNote(_ note: NoteSchema.Note) {
        do {
            try notesStore.delete(note)
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
        } catch {
            errorMessage = localized("Failed to delete note: %@", locale: locale).replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }
}

// MARK: - Sort Order

enum SortOrder {
    case ascending
    case descending
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
