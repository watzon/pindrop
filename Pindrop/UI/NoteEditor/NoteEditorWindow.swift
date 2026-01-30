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
            },
            onPinChange: { [weak self] isPinned in
                self?.updateWindowLevel(isPinned: isPinned)
            }
        )
        .modelContainer(container)
        
        let hostingController = NSHostingController(rootView: AnyView(contentView))
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = isNewNote ? "New Note" : (note?.title ?? "Note")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(AppColors.windowBackground)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 600, height: 500))
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        
        if note?.isPinned == true {
            window.level = .floating
        }
        
        self.hostingController = hostingController
        self.window = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func updateWindowLevel(isPinned: Bool) {
        window?.level = isPinned ? .floating : .normal
    }
    
    func close() {
        window?.close()
        onClose?()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose?()
        window = nil
        hostingController = nil
    }
}

struct NoteEditorView: View {
    
    let note: NoteSchema.Note?
    let isNewNote: Bool
    let onClose: () -> Void
    let onSave: (NoteSchema.Note) -> Void
    let onPinChange: (Bool) -> Void
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isPinned: Bool = false
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var currentNote: NoteSchema.Note?
    
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var contentFieldFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    
    init(
        note: NoteSchema.Note? = nil,
        isNewNote: Bool = false,
        onClose: @escaping () -> Void,
        onSave: @escaping (NoteSchema.Note) -> Void,
        onPinChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.note = note
        self.isNewNote = isNewNote
        self.onClose = onClose
        self.onSave = onSave
        self.onPinChange = onPinChange
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
                .foregroundStyle(AppColors.border)
            
            contentEditorView
        }
        .background(AppColors.windowBackground)
        .onAppear {
            loadNoteData()
            if isNewNote {
                createNoteIfNeeded()
                titleFieldFocused = true
            } else {
                contentFieldFocused = true
            }
        }
        .onChange(of: title) { _, _ in saveNote() }
        .onChange(of: content) { _, _ in saveNote() }
        .onChange(of: isPinned) { _, newValue in
            onPinChange(newValue)
            saveNote()
        }
        .onChange(of: tags) { _, _ in saveNote() }
    }
    
    private var headerView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                TextField("Note Title", text: $title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit {
                        contentFieldFocused = true
                    }
                
                Spacer(minLength: 0)
                
                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPinned ? AppColors.accent : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin from screen" : "Pin to screen (always on top)")
            }
            
            tagsRow
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceBackground)
    }
    
    @ViewBuilder
    private var tagsRow: some View {
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
    
    private var contentEditorView: some View {
        MarkdownEditor(text: $content)
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.contentBackground)
    }
    
    private func loadNoteData() {
        if let note = note {
            title = note.title
            content = note.content
            isPinned = note.isPinned
            tags = note.tags
            // Only set currentNote for existing notes - new notes need to be inserted into context first
            if !isNewNote {
                currentNote = note
            }
        }
    }
    
    private func createNoteIfNeeded() {
        guard isNewNote && currentNote == nil else { return }
        
        let newNote = NoteSchema.Note(
            title: title.isEmpty ? "Untitled Note" : title,
            content: content,
            tags: tags,
            isPinned: isPinned
        )
        modelContext.insert(newNote)
        currentNote = newNote
        
        do {
            try modelContext.save()
        } catch {
            Log.app.error("Failed to create note: \(error)")
        }
    }
    
    private func saveNote() {
        guard let noteToSave = currentNote else { return }
        
        noteToSave.title = title.isEmpty ? "Untitled Note" : title
        noteToSave.content = content
        noteToSave.isPinned = isPinned
        noteToSave.tags = tags
        noteToSave.updatedAt = Date()
        
        do {
            try modelContext.save()
            onSave(noteToSave)
        } catch {
            Log.app.error("Failed to save note: \(error)")
        }
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
}

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
        .background(AppColors.elevatedSurface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: 0.5))
    }
}

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
        content: "# Project Ideas\n\n1. **AI Dictation** app\n2. *Native* Mac experience\n3. `Open source`\n\nThese are some ideas for the next project.",
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
