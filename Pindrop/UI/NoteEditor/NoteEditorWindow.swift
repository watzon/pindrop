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
import Foundation

@MainActor
final class NoteEditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var modelContainer: ModelContainer?
    private var themeCancellable: AnyCancellable?

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

        // Always rebuild so ⌘N / open-from-history can replace an already-open editor.
        if window != nil {
            window?.delegate = nil
            window?.close()
            window = nil
            hostingController = nil
            themeCancellable = nil
        }

        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot show NoteEditorWindow")
            return
        }

        let appLocale = AppLocale.currentSelection()
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
        .environment(\.locale, appLocale.locale)
        .environment(\.layoutDirection, appLocale.layoutDirection)

        let hostingController = NSHostingController(rootView: AnyView(contentView))

        let window = NSWindow(contentViewController: hostingController)
        let locale = appLocale.locale
        Log.ui.infoVisible("Creating note editor window for locale=\(locale.identifier) isNewNote=\(isNewNote)")
        window.title = isNewNote ? localized("New Note", locale: locale) : (note?.title ?? localized("Note", locale: locale))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(AppColors.windowBackground)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 600, height: 500))
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        applyInterfaceLayoutDirection(to: window, locale: locale)

        if note?.isPinned == true {
            window.level = .floating
        }

        self.hostingController = hostingController
        self.window = window
        themeCancellable = PindropThemeController.shared.$revision.sink { [weak self] _ in
            guard let self else { return }
            PindropThemeController.shared.apply(to: self.window)
        }

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
        themeCancellable = nil
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
    @State private var showSavedConfirmation = false
    @State private var savedConfirmationTask: Task<Void, Never>?
    @State private var editorID = UUID()

    @ObservedObject private var appendListeningState = NoteAppendListeningCoordinator.shared.state

    @Environment(\.locale) private var locale
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

    private var isThisEditorListening: Bool {
        appendListeningState.activeEditorID == editorID
            && (appendListeningState.isListening || appendListeningState.isProcessing)
    }

    private var wordCountLabel: String {
        let count = content.wordCount
        if count == 1 {
            return localized("1 word", locale: locale)
        }
        let format = localized("%d words", locale: locale)
        return String(format: format, locale: locale, count)
    }

    private var listeningElapsedLabel: String {
        let total = Int(appendListeningState.elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .foregroundStyle(AppColors.border)

            contentEditorView

            Divider()
                .foregroundStyle(AppColors.border)

            footerView
        }
        .background(AppColors.windowBackground)
        .themeRefresh()
        .onAppear {
            loadNoteData()
            if isNewNote {
                createNoteIfNeeded()
                titleFieldFocused = true
            } else {
                contentFieldFocused = true
            }
        }
        .onDisappear {
            savedConfirmationTask?.cancel()
            if appendListeningState.activeEditorID == editorID {
                NoteAppendListeningCoordinator.shared.requestStop(editorID: editorID)
            }
        }
        .onChange(of: title) { _, _ in saveNote() }
        .onChange(of: content) { _, _ in saveNote() }
        .onChange(of: isPinned) { _, newValue in
            onPinChange(newValue)
            saveNote()
        }
        .onChange(of: tags) { _, _ in saveNote() }
        .onReceive(NotificationCenter.default.publisher(for: .noteSpeakToAppendTranscript)) { notification in
            guard let targetID = notification.userInfo?["editorID"] as? UUID,
                  targetID == editorID,
                  let text = notification.userInfo?["text"] as? String else { return }
            content = NoteContentAppend.append(transcript: text, to: content)
        }
    }

    private var headerView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                TextField(localized("Note Title", locale: locale), text: $title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit {
                        contentFieldFocused = true
                    }

                Spacer(minLength: 0)

                speakToAppendButton

                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isPinned ? AppColors.accent : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? localized("Unpin from screen", locale: locale) : localized("Pin to screen (always on top)", locale: locale))
            }

            tagsRow
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceBackground)
    }

    private var speakToAppendButton: some View {
        Button(action: toggleSpeakToAppend) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isThisEditorListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isThisEditorListening ? AppColors.error : AppColors.textSecondary)

                if isThisEditorListening {
                    if appendListeningState.isProcessing {
                        Text(localized("Processing…", locale: locale))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Text(listeningElapsedLabel)
                            .font(AppTypography.caption.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(
            isThisEditorListening
                ? localized("Stop listening", locale: locale)
                : localized("Speak to append", locale: locale)
        )
        .disabled(appendListeningState.isProcessing && isThisEditorListening)
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

                    TextField(localized("Add tag...", locale: locale), text: $newTag)
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

    private var footerView: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(wordCountLabel)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            Spacer(minLength: 0)

            if showSavedConfirmation {
                Text(localized("Saved", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                    .transition(.opacity)
            }

            Button(action: saveNow) {
                Text(localized("Save", locale: locale))
                    .font(AppTypography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
            .help(localized("Save now (⌘S)", locale: locale))
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.surfaceBackground)
        .animation(AppTheme.Animation.fast, value: showSavedConfirmation)
    }

    private func toggleSpeakToAppend() {
        if isThisEditorListening {
            NoteAppendListeningCoordinator.shared.requestStop(editorID: editorID)
        } else {
            NoteAppendListeningCoordinator.shared.requestStart(editorID: editorID)
        }
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

    private func saveNow() {
        saveNote()
        showSavedFlash()
    }

    private func showSavedFlash() {
        savedConfirmationTask?.cancel()
        withAnimation(AppTheme.Animation.fast) {
            showSavedConfirmation = true
        }
        savedConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(AppTheme.Animation.fast) {
                    showSavedConfirmation = false
                }
            }
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

/// Bridges note-editor speak-to-append UI requests to AppCoordinator via notifications.
@MainActor
enum NoteAppendListeningCoordinator {
    static let shared = NoteAppendListeningCoordinatorBox()
}

@MainActor
final class NoteAppendListeningCoordinatorBox {
    let state = NoteAppendListeningState()

    func requestStart(editorID: UUID) {
        NotificationCenter.default.post(
            name: .noteSpeakToAppendRequest,
            object: nil,
            userInfo: ["editorID": editorID, "action": "start"]
        )
    }

    func requestStop(editorID: UUID) {
        NotificationCenter.default.post(
            name: .noteSpeakToAppendRequest,
            object: nil,
            userInfo: ["editorID": editorID, "action": "stop"]
        )
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
        .hairlineBorder(Capsule(), style: AppColors.border)
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
