//
//  NoteEditorWindow.swift
//  Pindrop
//
//  Created on 2026-01-29.
//
//  Note editor window (U5 scorched-earth restyle, spec §10): 480×560 fixed,
//  Pinned badge, listening chip, footer word count + ⌘S hint.
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
        // Fixed 480×560 design size; keep modest min if user resizes.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(AppColors.contentBackground)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 480, height: 560))
        window.minSize = NSSize(width: 400, height: 420)
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
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedSnapshot: NoteSnapshot?
    @State private var editorID = UUID()
    @State private var lastEditedAt = Date()

    @ObservedObject private var appendListeningState = NoteAppendListeningCoordinator.shared.state

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var footerMetaLabel: String {
        let relative = NotesDateFormatting.compactRelative(
            from: lastEditedAt,
            locale: locale
        )
        return "\(wordCountLabel) · \(localized("edited", locale: locale)) \(relative)"
    }

    private var listeningElapsedLabel: String {
        let total = Int(appendListeningState.elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebarAccessory

            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isThisEditorListening {
                listeningChip
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }

            footerView
        }
        .background(AppColors.contentBackground)
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
            autosaveTask?.cancel()
            saveNote()
            if appendListeningState.activeEditorID == editorID {
                NoteAppendListeningCoordinator.shared.requestStop(editorID: editorID)
            }
        }
        .onChange(of: title) { _, _ in
            noteDidChange()
        }
        .onChange(of: content) { _, _ in
            noteDidChange()
        }
        .onChange(of: isPinned) { _, newValue in
            onPinChange(newValue)
            noteDidChange()
        }
        .onChange(of: tags) { _, _ in
            noteDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSpeakToAppendTranscript)) { notification in
            guard let targetID = notification.userInfo?["editorID"] as? UUID,
                  targetID == editorID,
                  let text = notification.userInfo?["text"] as? String else { return }
            content = NoteContentAppend.append(transcript: text, to: content)
        }
    }

    // MARK: - Titlebar (Pinned badge + pin toggle + speak)

    private var titlebarAccessory: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if isPinned {
                Text(localized("Pinned", locale: locale))
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(AppColors.accentBackground)
                    )
            }

            speakToAppendButton

            Button(action: { isPinned.toggle() }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isPinned ? AppColors.accent : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(isPinned
                  ? localized("Unpin from screen", locale: locale)
                  : localized("Pin to screen (always on top)", locale: locale))
            .accessibilityLabel(
                isPinned
                    ? localized("Unpin from screen", locale: locale)
                    : localized("Pin to screen (always on top)", locale: locale)
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 46)
        .background(AppColors.contentBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }

    private var speakToAppendButton: some View {
        Button(action: toggleSpeakToAppend) {
            HStack(spacing: 4) {
                Image(systemName: isThisEditorListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isThisEditorListening ? AppColors.recording : AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .help(
            isThisEditorListening
                ? localized("Stop listening", locale: locale)
                : localized("Speak to append", locale: locale)
        )
        .accessibilityLabel(
            isThisEditorListening
                ? localized("Stop listening", locale: locale)
                : localized("Speak to append", locale: locale)
        )
        .disabled(appendListeningState.isProcessing && isThisEditorListening)
    }

    // MARK: - Editor content

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(localized("Note Title", locale: locale), text: $title)
                .font(FontLoader.font(family: .newsreader, size: 22, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .textFieldStyle(.plain)
                .focused($titleFieldFocused)
                .onSubmit {
                    contentFieldFocused = true
                }

            tagsRow

            MarkdownEditor(text: $content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 432 + 48) // content ~432 + horizontal padding
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var tagsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
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

    // MARK: - Listening chip (spec §10)

    private var listeningChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.recording)
                .frame(width: 7, height: 7)

            if appendListeningState.isProcessing {
                Text(localized("Processing…", locale: locale))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                Text(localized("Listening — speak to append…", locale: locale))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer(minLength: 8)

            Text(listeningElapsedLabel)
                .font(AppTypography.monoSmall)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.accentBackground)
        )
    }

    // MARK: - Footer (spec §10)

    private var footerView: some View {
        HStack(spacing: 12) {
            Text(footerMetaLabel)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showSavedConfirmation {
                Text(localized("Saved", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                    .transition(.opacity)
            }

            Text(localized("⌘S to save", locale: locale))
                .font(AppTypography.monoSmall)
                .foregroundStyle(AppColors.textTertiary)
                .onTapGesture { saveNow() }
                .help(localized("Save now (⌘S)", locale: locale))
        }
        .padding(.horizontal, 24)
        .frame(height: 39)
        .background(AppColors.contentBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
        .background {
            Button(action: saveNow) { EmptyView() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .appAnimation(.fast, value: showSavedConfirmation)
    }

    // MARK: - Actions

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
            lastEditedAt = note.updatedAt
            if !isNewNote {
                currentNote = note
            }
            lastSavedSnapshot = NoteSnapshot(note: note)
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
            lastSavedSnapshot = NoteSnapshot(note: newNote)
        } catch {
            Log.app.error("Failed to create note: \(error)")
        }
    }

    private func saveNote() {
        guard let noteToSave = currentNote else { return }

        let snapshot = NoteSnapshot(
            title: title.isEmpty ? "Untitled Note" : title,
            content: content,
            isPinned: isPinned,
            tags: tags
        )
        guard snapshot != lastSavedSnapshot else { return }

        noteToSave.title = snapshot.title
        noteToSave.content = snapshot.content
        noteToSave.isPinned = snapshot.isPinned
        noteToSave.tags = snapshot.tags
        noteToSave.updatedAt = Date()

        do {
            try modelContext.save()
            lastSavedSnapshot = snapshot
            onSave(noteToSave)
        } catch {
            Log.app.error("Failed to save note: \(error)")
        }
    }

    private func saveNow() {
        autosaveTask?.cancel()
        saveNote()
        showSavedFlash()
    }

    private func noteDidChange() {
        lastEditedAt = Date()
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            saveNote()
        }
    }

    private func showSavedFlash() {
        savedConfirmationTask?.cancel()
        withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
            showSavedConfirmation = true
        }
        savedConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : AppTheme.Animation.fast) {
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

private struct NoteSnapshot: Equatable {
    let title: String
    let content: String
    let isPinned: Bool
    let tags: [String]

    init(note: NoteSchema.Note) {
        self.init(
            title: note.title,
            content: note.content,
            isPinned: note.isPinned,
            tags: note.tags
        )
    }

    init(title: String, content: String, isPinned: Bool, tags: [String]) {
        self.title = title
        self.content = content
        self.isPinned = isPinned
        self.tags = tags
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

    @Environment(\.locale) private var locale

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
            .accessibilityLabel(localized("Remove", locale: locale))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.windowBackground)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: 1))
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
    .frame(width: 480, height: 560)
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
    .frame(width: 480, height: 560)
    .modelContainer(container)
}
