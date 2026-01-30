//
//  NoteEditorWindow.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import SwiftData
import AppKit
import Combine

// MARK: - NoteEditorWindowController

@MainActor
final class NoteEditorWindowController: NSObject, NSWindowDelegate {
    
    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var modelContainer: ModelContainer?
    
    var onClose: (() -> Void)?
    var onSave: ((NoteSchema.Note) -> Void)?
    
    private var note: NoteSchema.Note?
    private var isNewNote: Bool = false
    
    override init() {
        super.init()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }
    
    func show(note: NoteSchema.Note? = nil, isNewNote: Bool = false) {
        self.note = note
        self.isNewNote = isNewNote
        
        // If window already exists, bring it to front
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot show NoteEditorWindow")
            return
        }
        
        let contentView = NoteEditorView(
            note: note,
            isNewNote: isNewNote,
            onClose: { [weak self] in
                self?.close()
            },
            onSave: { [weak self] (updatedNote: NoteSchema.Note) in
                self?.onSave?(updatedNote)
            }
        )
        .modelContainer(container)
        
        let hostingController = NSHostingController(rootView: AnyView(contentView))
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = isNewNote ? "New Note" : (note?.title ?? "Note")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(AppColors.accentBackground)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 600, height: 500))
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        
        self.hostingController = hostingController
        self.window = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
        onClose?()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        onClose?()
        window = nil
        hostingController = nil
    }
}

// MARK: - NoteEditorView

struct NoteEditorView: View {
    
    let note: NoteSchema.Note?
    let isNewNote: Bool
    let onClose: () -> Void
    let onSave: (NoteSchema.Note) -> Void
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isPinned: Bool = false
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var contentFieldFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    
    init(
        note: NoteSchema.Note? = nil,
        isNewNote: Bool = false,
        onClose: @escaping () -> Void,
        onSave: @escaping (NoteSchema.Note) -> Void
    ) {
        self.note = note
        self.isNewNote = isNewNote
        self.onClose = onClose
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title field and actions
            headerView
            
            Divider()
                .background(AppColors.divider)
            
            // Content editor
            contentEditorView
        }
        .background(AppColors.accentBackground)
        .onAppear {
            loadNoteData()
            if isNewNote {
                titleFieldFocused = true
            } else {
                contentFieldFocused = true
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Title field
                TextField("Note Title", text: $title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit {
                        contentFieldFocused = true
                    }
                
                Spacer(minLength: 0)
                
                // Pin button
                Button(action: togglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPinned ? AppColors.accent : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin note" : "Pin note")
                
                // Close button
                Button(action: saveAndClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Close editor")
            }
            
            // Tags row
            if !tags.isEmpty || !newTag.isEmpty {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "number")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(tags, id: \.self) { tag in
                                TagChip(tag: tag, onRemove: { removeTag(tag) })
                            }
                            
                            TextField("Add tag...", text: $newTag)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .textFieldStyle(.plain)
                                .frame(width: 80)
                                .onSubmit {
                                    addTag()
                                }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.accentBackground)
    }
    
    // MARK: - Content Editor View
    
    private var contentEditorView: some View {
        ScrollView {
            TextEditor(text: $content)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($contentFieldFocused)
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(AppTheme.Spacing.lg)
        }
        .background(AppColors.accentBackground)
    }
    
    // MARK: - Actions
    
    private func loadNoteData() {
        if let note = note {
            title = note.title
            content = note.content
            isPinned = note.isPinned
            tags = note.tags
        } else {
            title = ""
            content = ""
            isPinned = false
            tags = []
        }
    }
    
    private func togglePin() {
        isPinned.toggle()
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
        }
        newTag = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    private func saveAndClose() {
        let updatedNote: NoteSchema.Note
        
        if isNewNote {
            updatedNote = NoteSchema.Note(
                title: title.isEmpty ? "Untitled Note" : title,
                content: content,
                tags: tags,
                isPinned: isPinned
            )
            modelContext.insert(updatedNote)
        } else if let existingNote = note {
            existingNote.title = title.isEmpty ? "Untitled Note" : title
            existingNote.content = content
            existingNote.isPinned = isPinned
            existingNote.tags = tags
            existingNote.updatedAt = Date()
            updatedNote = existingNote
        } else {
            return
        }
        
        do {
            try modelContext.save()
        } catch {
            Log.app.error("Failed to save note: \(error)")
        }
        
        onSave(updatedNote)
        onClose()
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.surfaceBackground)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: 0.5))
    }
}

// MARK: - Preview

#Preview("NoteEditorView - New Note") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: NoteSchema.Note.self, configurations: config)
    
    return NoteEditorView(
        note: nil,
        isNewNote: true,
        onClose: {},
        onSave: { _ in }
    )
    .frame(width: 600, height: 500)
    .modelContainer(container)
}

#Preview("NoteEditorView - Existing Note") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: NoteSchema.Note.self, configurations: config)
    let note = NoteSchema.Note(
        title: "Project Ideas",
        content: "1. AI Dictation app\n2. Native Mac experience\n3. Open source\n\nThese are some ideas for the next project.",
        tags: ["ideas", "dev"],
        isPinned: true
    )
    
    return NoteEditorView(
        note: note,
        isNewNote: false,
        onClose: {},
        onSave: { _ in }
    )
    .frame(width: 600, height: 500)
    .modelContainer(container)
}
