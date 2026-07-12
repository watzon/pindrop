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

    /// Process-wide weak set of editors that still own a live window/hosting controller.
    /// Used at quit so unscheduled drafts can be force-closed and enqueued before flush.
    private static let liveEditors = NSHashTable<NoteEditorWindowController>.weakObjects()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var modelContainer: ModelContainer?
    private var themeCancellable: AnyCancellable?

    var onClose: (() -> Void)?
    var onSave: ((NoteSchema.Note) -> Void)?

    private var note: NoteSchema.Note?
    private var isNewNote: Bool = false
    /// Note currently hosted by this window (for replacement flush ordering).
    private var openNoteModelID: PersistentIdentifier?
    /// Bumps on every `show` so a superseded replacement presentation aborts.
    private var presentationGeneration: UInt = 0

    override init() {
        super.init()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func show(note: NoteSchema.Note? = nil, isNewNote: Bool = false) {
        self.note = note
        self.isNewNote = isNewNote

        presentationGeneration &+= 1
        let generation = presentationGeneration
        let previousModelID = openNoteModelID

        // Always rebuild so ⌘N / open-from-history can replace an already-open editor.
        // Close first so the view can enqueue its newest draft, then await durability
        // before presenting the replacement — preventing stale close writes from racing.
        if window != nil {
            Task { @MainActor in
                self.tearDownWindow(notifyClose: false)
                if let previousModelID {
                    await NoteEditorPersistenceController.shared.flush(modelID: previousModelID)
                }
                guard generation == self.presentationGeneration else { return }
                self.presentEditor(note: note, isNewNote: isNewNote)
            }
            return
        }

        presentEditor(note: note, isNewNote: isNewNote)
    }

    private func presentEditor(note: NoteSchema.Note?, isNewNote: Bool) {
        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot show NoteEditorWindow")
            return
        }

        openNoteModelID = note?.persistentModelID

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
        registerAsLive()
        themeCancellable = PindropThemeController.shared.$revision.sink { [weak self] _ in
            guard let self else { return }
            PindropThemeController.shared.apply(to: self.window)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func tearDownWindow(notifyClose: Bool) {
        unregisterAsLive()
        if notifyClose {
            onClose?()
        }
        // Keep openNoteModelID for the caller that is about to flush; clear after.
        // Always close — including hidden/orderOut windows — so termination does
        // not skip drafts merely because the window is not visible/miniaturized.
        // Hosting controller stays attached until after close so onDisappear can
        // still act as a redundant normal-close enqueue path.
        window?.close()
        window = nil
        hostingController = nil
        themeCancellable = nil
        openNoteModelID = nil
    }

    private func updateWindowLevel(isPinned: Bool) {
        window?.level = isPinned ? .floating : .normal
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        unregisterAsLive()
        let modelID = openNoteModelID
        openNoteModelID = nil
        window = nil
        // Drop the hosting controller so SwiftUI onDisappear enqueues the final draft
        // onto the shared owner before we await durability.
        hostingController = nil
        themeCancellable = nil

        Task { @MainActor in
            // Flush any close-enqueued draft; tracked-draft termination does not
            // depend on this path or Task.yield ordering.
            if let modelID {
                await NoteEditorPersistenceController.shared.flush(modelID: modelID)
            }
            self.onClose?()
        }
    }

    /// Force-close every live editor while the hosting controller is still attached.
    /// onDisappear remains a redundant normal-close path; tracked drafts are the source of truth.
    fileprivate static func closeAllLiveEditorsForTermination() {
        let controllers = liveEditors.allObjects
        for controller in controllers {
            // notifyClose: false — app is quitting; no UI bookkeeping needed.
            controller.tearDownWindow(notifyClose: false)
        }
        liveEditors.removeAllObjects()
    }

    private func registerAsLive() {
        Self.liveEditors.add(self)
    }

    private func unregisterAsLive() {
        Self.liveEditors.remove(self)
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
    /// Displayed word count — updated independently of Markdown editor rendering.
    @State private var displayedWordCount = 0
    @State private var wordCountTask: Task<Void, Never>?

    /// Ownership + processing only — does NOT observe 4Hz `elapsed` ticks.
    @ObservedObject private var appendSessionState = NoteAppendListeningCoordinator.shared.sessionState

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
        appendSessionState.activeEditorID == editorID
            && (appendSessionState.isListening || appendSessionState.isProcessing)
    }

    private var wordCountLabel: String {
        let count = displayedWordCount
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

    var body: some View {
        VStack(spacing: 0) {
            titlebarAccessory

            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isThisEditorListening {
                NoteAppendListeningChip(
                    isProcessing: appendSessionState.isProcessing
                )
                .padding(.horizontal, 24)
                .padding(.top, 6)
            }

            footerView
        }
        .background(AppColors.contentBackground)
        .themeRefresh()
        .onAppear {
            // Await any in-flight close write for this note before loading so a
            // reopened editor never starts from a pre-close snapshot.
            if let existing = note {
                let modelID = existing.persistentModelID
                Task { @MainActor in
                    await NoteEditorPersistenceController.shared.flush(modelID: modelID)
                    if let refreshed = modelContext.model(for: modelID) as? NoteSchema.Note {
                        title = refreshed.title
                        content = refreshed.content
                        isPinned = refreshed.isPinned
                        tags = refreshed.tags
                        lastEditedAt = refreshed.updatedAt
                        if !isNewNote {
                            currentNote = refreshed
                        }
                        lastSavedSnapshot = NoteSnapshot(note: refreshed)
                        displayedWordCount = refreshed.content.wordCount
                    } else {
                        loadNoteData()
                        refreshWordCountImmediately()
                    }
                    if isNewNote {
                        createNoteIfNeeded()
                        titleFieldFocused = true
                    } else {
                        contentFieldFocused = true
                    }
                }
            } else {
                loadNoteData()
                refreshWordCountImmediately()
                if isNewNote {
                    createNoteIfNeeded()
                    titleFieldFocused = true
                } else {
                    contentFieldFocused = true
                }
            }
        }
        .onDisappear {
            savedConfirmationTask?.cancel()
            autosaveTask?.cancel()
            wordCountTask?.cancel()
            // Synchronously enqueue the newest draft on the shared owner, then
            // retain a flush task so close/quit can await durability.
            enqueueCloseSaveIfNeeded()
            if appendSessionState.activeEditorID == editorID {
                NoteAppendListeningCoordinator.shared.requestStop(editorID: editorID)
            }
        }
        .onChange(of: title) { _, _ in
            noteDidChange()
        }
        .onChange(of: content) { _, newValue in
            scheduleWordCountUpdate(for: newValue)
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
        .disabled(appendSessionState.isProcessing && isThisEditorListening)
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
            displayedWordCount = note.content.wordCount
        } else {
            displayedWordCount = 0
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

    /// Persist the current draft. When `immediate` is false this is called after the 500ms debounce.
    private func saveNote(immediate: Bool = false) {
        guard let noteToSave = currentNote else { return }

        let snapshot = currentSnapshot()
        guard snapshot != lastSavedSnapshot else {
            if immediate {
                // Still await any in-flight write for Cmd-S / close bookkeeping.
                let modelID = noteToSave.persistentModelID
                Task { @MainActor in
                    await NoteEditorPersistenceController.shared.flush(modelID: modelID)
                }
            }
            return
        }

        let modelID = noteToSave.persistentModelID
        let editedAt = lastEditedAt
        let container = modelContext.container

        // Optimistic local bookkeeping so subsequent keystrokes compare against the pending draft.
        lastSavedSnapshot = snapshot

        if immediate {
            // Close / Cmd-S: await the shared owner so the newest snapshot is durable
            // before teardown or feedback completes.
            Task { @MainActor in
                let result = await NoteEditorPersistenceController.shared.saveAndWait(
                    container: container,
                    modelID: modelID,
                    snapshot: snapshot,
                    editedAt: editedAt
                )
                await handlePersistenceResult(
                    result,
                    modelID: modelID,
                    noteToSave: noteToSave,
                    snapshot: snapshot,
                    editedAt: editedAt
                )
            }
        } else {
            // Nonblocking 500ms autosave path — generation arbitration lives on the shared owner.
            let task = NoteEditorPersistenceController.shared.scheduleSave(
                container: container,
                modelID: modelID,
                snapshot: snapshot,
                editedAt: editedAt
            )
            Task { @MainActor in
                let result = await task.value
                await handlePersistenceResult(
                    result,
                    modelID: modelID,
                    noteToSave: noteToSave,
                    snapshot: snapshot,
                    editedAt: editedAt
                )
            }
        }
    }

    /// Enqueue the latest draft during disappear so a subsequent flush can await it.
    private func enqueueCloseSaveIfNeeded() {
        guard let noteToSave = currentNote else { return }
        let snapshot = currentSnapshot()
        guard snapshot != lastSavedSnapshot else { return }

        lastSavedSnapshot = snapshot
        _ = NoteEditorPersistenceController.shared.scheduleSave(
            container: modelContext.container,
            modelID: noteToSave.persistentModelID,
            snapshot: snapshot,
            editedAt: lastEditedAt
        )
    }

    private func currentSnapshot() -> NoteSnapshot {
        NoteSnapshot(
            title: title.isEmpty ? "Untitled Note" : title,
            content: content,
            isPinned: isPinned,
            tags: tags
        )
    }

    private func handlePersistenceResult(
        _ result: NotePersistenceResult?,
        modelID: PersistentIdentifier,
        noteToSave: NoteSchema.Note,
        snapshot: NoteSnapshot,
        editedAt: Date
    ) async {
        guard let result else {
            // Roll back optimistic snapshot so the next save attempt retries.
            if lastSavedSnapshot == snapshot {
                lastSavedSnapshot = nil
            }
            return
        }

        // Drop stale completions — a newer edit already supersedes this save.
        guard result.applied,
              result.generation == NoteEditorPersistenceController.shared.currentGeneration(for: modelID)
        else { return }

        // Refresh the managed model from the main context for the onSave callback.
        if let refreshed = modelContext.model(for: modelID) as? NoteSchema.Note {
            onSave(refreshed)
        } else {
            noteToSave.title = snapshot.title
            noteToSave.content = snapshot.content
            noteToSave.isPinned = snapshot.isPinned
            noteToSave.tags = snapshot.tags
            noteToSave.updatedAt = result.updatedAt ?? editedAt
            onSave(noteToSave)
        }
    }

    private func saveNow() {
        autosaveTask?.cancel()
        saveNote(immediate: true)
        showSavedFlash()
    }

    private func noteDidChange() {
        lastEditedAt = Date()
        // Capture the latest draft synchronously before the 500ms debounce so quit
        // can persist mid-debounce edits without relying on onDisappear timing.
        if let noteToSave = currentNote {
            NoteEditorPersistenceController.shared.trackDraft(
                container: modelContext.container,
                modelID: noteToSave.persistentModelID,
                snapshot: currentSnapshot(),
                editedAt: lastEditedAt
            )
        }
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            saveNote(immediate: false)
        }
    }

    private func scheduleWordCountUpdate(for text: String) {
        wordCountTask?.cancel()
        // Short debounce so footer updates lag typing slightly without rescanning every keystroke.
        wordCountTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let count = text.wordCount
            if displayedWordCount != count {
                displayedWordCount = count
            }
        }
    }

    private func refreshWordCountImmediately() {
        wordCountTask?.cancel()
        displayedWordCount = content.wordCount
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

// MARK: - Listening chip (isolated elapsed observation)

/// Small child that alone observes 4Hz `elapsed` ticks from `NoteAppendListeningState`.
/// Keeps Markdown editor / root from invalidating on every duration update.
private struct NoteAppendListeningChip: View {
    let isProcessing: Bool

    @ObservedObject private var listeningState = NoteAppendListeningCoordinator.shared.state
    @Environment(\.locale) private var locale

    private var elapsedLabel: String {
        let total = Int(listeningState.elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.recording)
                .frame(width: 7, height: 7)

            if isProcessing {
                Text(localized("Processing…", locale: locale))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                Text(localized("Listening — speak to append…", locale: locale))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer(minLength: 8)

            Text(elapsedLabel)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isProcessing
                ? localized("Processing…", locale: locale)
                : localized("Listening — speak to append…", locale: locale)
        )
        .accessibilityValue(elapsedLabel)
    }
}

// MARK: - Snapshots & shared background persistence

struct NoteSnapshot: Equatable, Sendable {
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

struct NotePersistenceResult: Sendable {
    let applied: Bool
    let generation: UInt
    let updatedAt: Date?
}

enum NoteEditorPersistenceError: Error {
    case noteMissing
}

/// Shared per-process note-editor persistence owner.
///
/// Serializes generation / edited-at arbitration across editor instances for the
/// same note so a close write from a destroyed view cannot overwrite a newer
/// reopened edit. Pending tasks are retained here (not on the SwiftUI view) so
/// close/quit can await durability after the editor is torn down.
///
/// Tracked drafts hold the latest value snapshot independently of debounce and
/// `onDisappear`, so termination can enqueue mid-edit state even when SwiftUI
/// lifecycle callbacks are delayed or skipped.
@MainActor
final class NoteEditorPersistenceController {
    static let shared = NoteEditorPersistenceController()

    private struct TrackedDraft {
        let container: ModelContainer
        var snapshot: NoteSnapshot
        var editedAt: Date
    }

    private var actors: [ObjectIdentifier: NoteEditorPersistenceActor] = [:]
    private var generations: [PersistentIdentifier: UInt] = [:]
    /// Newest edit timestamp accepted at the scheduling boundary for each note.
    /// Rejects later-enqueued but earlier-edited snapshots regardless of generation.
    private var newestAcceptedEditedAt: [PersistentIdentifier: Date] = [:]
    private var pendingSaves: [PersistentIdentifier: Task<NotePersistenceResult?, Never>] = [:]
    /// Latest unsaved (or not-yet-confirmed) draft per note, updated synchronously
    /// on every editor change. Tracking performs no I/O.
    private var trackedDrafts: [PersistentIdentifier: TrackedDraft] = [:]

    private init() {}

    /// Highest generation scheduled for `modelID` (0 if none).
    func currentGeneration(for modelID: PersistentIdentifier) -> UInt {
        generations[modelID] ?? 0
    }

    /// Synchronously record the latest draft values for termination durability.
    /// Keeps the newer `editedAt` when a stale track races a fresher one. No I/O.
    func trackDraft(
        container: ModelContainer,
        modelID: PersistentIdentifier,
        snapshot: NoteSnapshot,
        editedAt: Date
    ) {
        if let existing = trackedDrafts[modelID], editedAt < existing.editedAt {
            return
        }
        trackedDrafts[modelID] = TrackedDraft(
            container: container,
            snapshot: snapshot,
            editedAt: editedAt
        )
    }

    /// Nonblocking enqueue used by the 500ms autosave path and close disappear.
    @discardableResult
    func scheduleSave(
        container: ModelContainer,
        modelID: PersistentIdentifier,
        snapshot: NoteSnapshot,
        editedAt: Date
    ) -> Task<NotePersistenceResult?, Never> {
        // Edit-time ordering at the scheduling boundary: a later-scheduled but
        // earlier-edited snapshot must not bump generation or replace pending work.
        if let newest = newestAcceptedEditedAt[modelID], editedAt < newest {
            let generation = generations[modelID] ?? 0
            return Task { @MainActor in
                NotePersistenceResult(applied: false, generation: generation, updatedAt: nil)
            }
        }
        if let newest = newestAcceptedEditedAt[modelID] {
            if editedAt > newest {
                newestAcceptedEditedAt[modelID] = editedAt
            }
        } else {
            newestAcceptedEditedAt[modelID] = editedAt
        }

        generations[modelID, default: 0] &+= 1
        let generation = generations[modelID] ?? 0
        let actor = persistenceActor(for: container)

        let task = Task<NotePersistenceResult?, Never> { @MainActor in
            do {
                let result = try await actor.save(
                    modelID: modelID,
                    snapshot: snapshot,
                    editedAt: editedAt,
                    generation: generation
                )
                if result.applied {
                    self.clearTrackedDraftIfApplied(
                        modelID: modelID,
                        snapshot: snapshot,
                        editedAt: editedAt
                    )
                }
                return result
            } catch {
                Log.app.error("Failed to save note: \(error)")
                return nil
            }
        }
        pendingSaves[modelID] = task
        return task
    }

    /// Schedule the newest snapshot and await its completion (Cmd-S / explicit flush).
    @discardableResult
    func saveAndWait(
        container: ModelContainer,
        modelID: PersistentIdentifier,
        snapshot: NoteSnapshot,
        editedAt: Date
    ) async -> NotePersistenceResult? {
        let task = scheduleSave(
            container: container,
            modelID: modelID,
            snapshot: snapshot,
            editedAt: editedAt
        )
        return await task.value
    }

    /// Await the newest in-flight save for a note (close / reopen / quit).
    func flush(modelID: PersistentIdentifier) async {
        await pendingSaves[modelID]?.value
    }

    /// Await every in-flight note save — used after termination enqueue.
    func flushAll() async {
        let tasks = Array(pendingSaves.values)
        for task in tasks {
            _ = await task.value
        }
    }

    /// Application termination: enqueue every tracked latest draft independently of
    /// SwiftUI `onDisappear`, close every registered window (any visibility),
    /// re-enqueue tracked drafts to absorb synchronous final updates, then await
    /// the resulting latest save task for each tracked note.
    func prepareForTermination() async {
        enqueueAllTrackedDrafts()
        NoteEditorWindowController.closeAllLiveEditorsForTermination()
        // Post-close re-enqueue absorbs any synchronous final track/update from
        // close handlers without relying on Task.yield or onDisappear ordering.
        enqueueAllTrackedDrafts()

        // Await the latest save task for every note still tracked after the
        // post-close enqueue — not a one-time snapshot of pre-close pendings.
        let modelIDs = Array(trackedDrafts.keys)
        for modelID in modelIDs {
            await pendingSaves[modelID]?.value
        }
    }

    /// Test seam: drop retained bookkeeping between deterministic cases.
    func resetForTesting() {
        actors.removeAll(keepingCapacity: false)
        generations.removeAll(keepingCapacity: false)
        newestAcceptedEditedAt.removeAll(keepingCapacity: false)
        pendingSaves.removeAll(keepingCapacity: false)
        trackedDrafts.removeAll(keepingCapacity: false)
    }

    /// Schedule every currently tracked draft. Pure scheduling — no await.
    private func enqueueAllTrackedDrafts() {
        let drafts = trackedDrafts
        for (modelID, draft) in drafts {
            _ = scheduleSave(
                container: draft.container,
                modelID: modelID,
                snapshot: draft.snapshot,
                editedAt: draft.editedAt
            )
        }
    }

    /// Drop a tracked draft only when the exact applied snapshot+timestamp is durable.
    private func clearTrackedDraftIfApplied(
        modelID: PersistentIdentifier,
        snapshot: NoteSnapshot,
        editedAt: Date
    ) {
        guard let tracked = trackedDrafts[modelID] else { return }
        // Keep any draft that is not exactly the save that just applied:
        // newer timestamps (still unsaved) and same-time different snapshots.
        guard tracked.editedAt == editedAt, tracked.snapshot == snapshot else {
            return
        }
        trackedDrafts.removeValue(forKey: modelID)
    }

    private func persistenceActor(for container: ModelContainer) -> NoteEditorPersistenceActor {
        let key = ObjectIdentifier(container)
        if let existing = actors[key] {
            return existing
        }
        let created = NoteEditorPersistenceActor(modelContainer: container)
        actors[key] = created
        return created
    }
}

/// Dedicated SwiftData model actor for note autosave.
/// Accepts only persistent model IDs and value snapshots — never managed models.
/// Generation arbitration is shared via `NoteEditorPersistenceController`.
@ModelActor
actor NoteEditorPersistenceActor {
    /// Highest generation observed per model ID (rejects in-flight stale drafts).
    private var latestGeneration: [PersistentIdentifier: UInt] = [:]
    private var lastAppliedEditedAt: [PersistentIdentifier: Date] = [:]

    func save(
        modelID: PersistentIdentifier,
        snapshot: NoteSnapshot,
        editedAt: Date,
        generation: UInt
    ) throws -> NotePersistenceResult {
        // Reject stale drafts before touching the store so an older in-flight
        // save cannot overwrite a newer edit that has already been scheduled.
        if let previous = latestGeneration[modelID], generation < previous {
            return NotePersistenceResult(applied: false, generation: generation, updatedAt: nil)
        }
        // Edit-time ordering is independent of generation: a higher generation
        // with an older editedAt still loses to the last applied edit.
        if let previousEdit = lastAppliedEditedAt[modelID], editedAt < previousEdit {
            return NotePersistenceResult(applied: false, generation: generation, updatedAt: nil)
        }
        latestGeneration[modelID] = generation

        guard let note = modelContext.model(for: modelID) as? NoteSchema.Note else {
            throw NoteEditorPersistenceError.noteMissing
        }

        // Re-check after model fetch: a newer generation may have arrived while we waited.
        if latestGeneration[modelID] != generation {
            return NotePersistenceResult(applied: false, generation: generation, updatedAt: nil)
        }

        // Skip no-op writes when store already matches the snapshot (except updatedAt).
        let alreadyCurrent =
            note.title == snapshot.title
            && note.content == snapshot.content
            && note.isPinned == snapshot.isPinned
            && note.tags == snapshot.tags
        let tagsChanged = note.tags != snapshot.tags

        let updatedAt: Date
        if alreadyCurrent {
            updatedAt = note.updatedAt
        } else {
            note.title = snapshot.title
            note.content = snapshot.content
            note.isPinned = snapshot.isPinned
            note.tags = snapshot.tags
            // Prefer the edit timestamp captured on the main actor for last-edit semantics.
            updatedAt = editedAt
            note.updatedAt = updatedAt
            // Final generation gate immediately before commit.
            if latestGeneration[modelID] != generation {
                // Discard local mutations; a newer save owns the store.
                modelContext.rollback()
                return NotePersistenceResult(applied: false, generation: generation, updatedAt: nil)
            }
            try modelContext.save()
            if tagsChanged {
                NotificationCenter.default.post(name: .pindropNoteTagsDidChange, object: nil)
            }
        }

        lastAppliedEditedAt[modelID] = editedAt
        return NotePersistenceResult(applied: true, generation: generation, updatedAt: updatedAt)
    }
}

/// Bridges note-editor speak-to-append UI requests to AppCoordinator via notifications.
@MainActor
enum NoteAppendListeningCoordinator {
    static let shared = NoteAppendListeningCoordinatorBox()
}

/// Session ownership / processing flags without publishing 4Hz elapsed ticks.
@MainActor
final class NoteAppendSessionState: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isProcessing = false
    @Published private(set) var activeEditorID: UUID?

    fileprivate func apply(isListening: Bool, isProcessing: Bool, activeEditorID: UUID?) {
        if self.isListening != isListening { self.isListening = isListening }
        if self.isProcessing != isProcessing { self.isProcessing = isProcessing }
        if self.activeEditorID != activeEditorID { self.activeEditorID = activeEditorID }
    }
}

@MainActor
final class NoteAppendListeningCoordinatorBox {
    let state = NoteAppendListeningState()
    /// Lightweight mirror of ownership/processing for the editor root (no elapsed).
    let sessionState = NoteAppendSessionState()

    private var sessionStateCancellable: AnyCancellable?

    init() {
        // All source mutations are main-actor isolated, so mirror synchronously.
        // Scheduling onto RunLoop.main introduced a stale-state window between a
        // session transition and the editor deciding whether Start or Stop applies.
        sessionStateCancellable = state.$isListening
            .combineLatest(state.$isProcessing, state.$activeEditorID)
            .sink { [weak self] isListening, isProcessing, activeEditorID in
                guard let self else { return }
                self.sessionState.apply(
                    isListening: isListening,
                    isProcessing: isProcessing,
                    activeEditorID: activeEditorID
                )
            }
    }

    deinit {
        sessionStateCancellable?.cancel()
    }

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
