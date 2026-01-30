//
//  NotesView.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    
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
    
    private var pinnedNotes: [NoteSchema.Note] {
        filteredNotes.filter { $0.isPinned }
    }
    
    private var unpinnedNotes: [NoteSchema.Note] {
        filteredNotes.filter { !$0.isPinned }
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
        VStack(spacing: 0) {
            // Header with search and actions
            headerSection
            
            // Content
            contentArea
        }
        .background(AppColors.contentBackground)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Notes")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(filteredNotes.count) notes")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                // Sort toggle button
                Button(action: toggleSortOrder) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: sortOrder == .ascending ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12))
                        Text("Date \(sortOrder == .ascending ? "↑" : "↓")")
                            .font(AppTypography.subheadline)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .buttonStyle(.borderless)
                .background(AppColors.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(AppColors.border, lineWidth: 0.5)
                )
                .help("Toggle sort order")
                
                // New Note button
                Button(action: createNewNote) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Note")
                            .font(AppTypography.subheadline)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .controlSize(.regular)
            }
            
            // Search bar
            searchBar
        }
        .padding(AppTheme.Spacing.xxl)
        .background(AppColors.contentBackground)
    }
    
    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            
            TextField("Search notes...", text: $searchText)
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
        .background(AppColors.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
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
            
            Text("Something went wrong")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button("Dismiss") {
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
            
            Text(searchText.isEmpty ? "No notes yet" : "No results found")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(searchText.isEmpty
                 ? "Create your first note to get started"
                 : "Try a different search term")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            
            if searchText.isEmpty {
                Button("Create New Note") {
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
            LazyVStack(spacing: AppTheme.Spacing.xxl, pinnedViews: .sectionHeaders) {
                // Pinned notes section
                if !pinnedNotes.isEmpty {
                    Section {
                        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.md) {
                            ForEach(pinnedNotes) { note in
                                NoteCardView(
                                    note: note,
                                    isSelected: selectedNote?.id == note.id,
                                    onOpen: { openNote(note) },
                                    onDelete: { deleteNote(note) },
                                    onTogglePin: { togglePin(note) }
                                )
                            }
                        }
                    } header: {
                        sectionHeader("Pinned")
                    }
                }
                
                // Unpinned notes section
                if !unpinnedNotes.isEmpty {
                    Section {
                        LazyVGrid(columns: gridColumns, spacing: AppTheme.Spacing.md) {
                            ForEach(unpinnedNotes) { note in
                                NoteCardView(
                                    note: note,
                                    isSelected: selectedNote?.id == note.id,
                                    onOpen: { openNote(note) },
                                    onDelete: { deleteNote(note) },
                                    onTogglePin: { togglePin(note) }
                                )
                            }
                        }
                    } header: {
                        if !pinnedNotes.isEmpty {
                            sectionHeader("All Notes")
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xxl)
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.5)
            
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.contentBackground)
    }
    
    // MARK: - Actions
    
    private func toggleSortOrder() {
        withAnimation(AppTheme.Animation.fast) {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        }
    }
    
    private func createNewNote() {
        let editorController = NoteEditorWindowController()
        editorController.show(note: nil, isNewNote: true)
        
        editorController.onClose = {
            // Note is automatically saved by the editor
        }
        
        editorController.onSave = { _ in
            // Note saved successfully
        }
    }
    
    private func openNote(_ note: NoteSchema.Note) {
        selectedNote = note
        
        let editorController = NoteEditorWindowController()
        editorController.show(note: note, isNewNote: false)
        
        editorController.onClose = { [weak note] in
            if note == nil {
                selectedNote = nil
            }
        }
        
        editorController.onSave = { _ in
            // Note saved successfully
        }
    }
    
    private func deleteNote(_ note: NoteSchema.Note) {
        do {
            try notesStore.delete(note)
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
        }
    }
    
    private func togglePin(_ note: NoteSchema.Note) {
        do {
            try notesStore.togglePin(note)
        } catch {
            errorMessage = "Failed to toggle pin: \(error.localizedDescription)"
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
