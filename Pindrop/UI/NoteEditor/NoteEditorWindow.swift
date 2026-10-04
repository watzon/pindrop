//
//  NoteEditorWindow.swift
//  Pindrop
//
//  Created on 2026-01-29.
//
//  Note editor window (U5 scorched-earth restyle, spec §10): document-style,
//  margin heading markers, listening chip, footer word count + ⌘S hint.
//

import SwiftUI
import SwiftData
import AppKit
import Combine
import Foundation
import PindropCore
import PindropData

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
        // Document-style window (Granola-class notes), not a fixed Post-it:
        // comfortable default size with a modest minimum for small screens.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor(AppColors.contentBackground)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 680, height: 760))
        window.minSize = NSSize(width: 460, height: 480)
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
    @State private var appendRequestState = NoteAppendEditorRequestState()
    @State private var appendStartPreflightTask: Task<Void, Never>?
    @State private var appendStopFlushTask: Task<Void, Never>?
    @State private var lastEditedAt = Date()
    /// Displayed word count — updated independently of Markdown editor rendering.
    @State private var displayedWordCount = 0
    @State private var wordCountTask: Task<Void, Never>?
    /// Immutable meeting-note citations rendered separately from the editable body.
    @State private var generatedCitations: [MeetingNoteCitation] = []
    /// Exact human-anchor snapshot that the meeting-note derivation consumed.
    @State private var generatedHumanAnchorContent = ""
    /// Invalidates citation lookups when the displayed note, title, or body changes.
    @State private var citationValidationGeneration: UInt = 0

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
        self._currentNote = State(initialValue: note)
        self.isNewNote = isNewNote
        self.onClose = onClose
        self.onSave = onSave
        self.onPinChange = onPinChange
    }
    private var isThisEditorListening: Bool {
        appendSessionState.activeEditorID == editorID
            && appendSessionState.activeNoteID == currentNote?.id
            && (appendSessionState.isListening || appendSessionState.isProcessing)
    }

    private var isAppendRequested: Bool {
        appendRequestState.isLocked(for: currentNote?.id)
    }

    private var isAppendLocked: Bool {
        isAppendRequested || isThisEditorListening
    }

    private var shouldStopSpeakToAppend: Bool {
        isAppendRequested || isThisEditorListening
    }

    private var wordCountLabel: String {
        let count = displayedWordCount
        if count == 1 {
            return localized("1 word", locale: locale)
        }
        let format = localized("%d words", locale: locale)
        return String(format: format, locale: locale, count)
    }

    /// Built from `NotesDateFormatting.editedLabel` on purpose. Composing this
    /// from a bare `localized("edited")` resolved to the "Edited" stat label,
    /// because that slug is already taken; the format key carries the lowercase
    /// running copy.
    private var footerMetaLabel: String {
        let edited = NotesDateFormatting.editedLabel(
            date: lastEditedAt,
            locale: locale
        )
        return "\(wordCountLabel) · \(edited)"
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
                let loadValidationGeneration = citationValidationGeneration
                Task { @MainActor in
                    await NoteEditorPersistenceController.shared.flush(modelID: modelID)
                    guard citationValidationGeneration == loadValidationGeneration,
                          currentNote?.persistentModelID == modelID,
                          currentNote?.id == existing.id
                    else {
                        return
                    }
                    if let refreshed = modelContext.model(for: modelID) as? NoteSchema.Note {
                        title = refreshed.title
                        content = refreshed.content
                        isPinned = refreshed.isPinned
                        tags = refreshed.tags
                        lastEditedAt = refreshed.updatedAt
                        currentNote = refreshed
                        lastSavedSnapshot = NoteSnapshot(note: refreshed)
                        displayedWordCount = refreshed.content.wordCount
                        loadMeetingCitations(for: refreshed.id, expectedContent: refreshed.content)
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
        .onChange(of: note?.id) { _, _ in
            invalidateCitationValidation(clearingCitations: true)
            loadNoteData()
            refreshWordCountImmediately()
        }

        .onDisappear {
            savedConfirmationTask?.cancel()
            let requestedNoteID = appendRequestState.requestedNoteID
            appendStartPreflightTask?.cancel()
            appendStartPreflightTask = nil
            appendStopFlushTask?.cancel()
            appendStopFlushTask = nil
            autosaveTask?.cancel()
            wordCountTask?.cancel()
            // Synchronously enqueue the newest draft on the shared owner, then
            // retain a flush task so close/quit can await durability.
            enqueueCloseSaveIfNeeded()
            if let noteID = requestedNoteID
                ?? (isThisEditorListening ? currentNote?.id : nil) {
                NoteAppendListeningCoordinator.shared.requestStop(
                    editorID: editorID,
                    noteID: noteID
                )
            }
        }
        .onChange(of: title) { _, newValue in
            invalidateCitationValidation(title: newValue)
            noteDidChange()
        }
        .onChange(of: content) { _, newValue in
            invalidateCitationValidation(body: newValue)
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
        .onChange(of: appendSessionState.isListening) { _, _ in
            clearAppendRequestAfterSessionFinish()
        }
        .onChange(of: appendSessionState.isProcessing) { _, _ in
            clearAppendRequestAfterSessionFinish()
        }
        .onChange(of: appendSessionState.activeEditorID) { _, _ in
            clearAppendRequestAfterSessionFinish()
        }
        .onChange(of: appendSessionState.activeNoteID) { _, _ in
            clearAppendRequestAfterSessionFinish()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSpeakToAppendTranscript)) { notification in
            applyCommittedAppend(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSpeakToAppendRejected)) { notification in
            guard let payload = NoteAppendRejectedPayload(notification: notification),
                  let requestedNoteID = appendRequestState.requestedNoteID,
                  payload.matches(editorID: editorID, noteID: requestedNoteID)
            else {
                return
            }

            appendRequestState.clearAfterStartRejected(noteID: payload.noteID)
            appendStartPreflightTask?.cancel()
            appendStartPreflightTask = nil
            appendStopFlushTask?.cancel()
            appendStopFlushTask = nil
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
            .disabled(isAppendLocked)
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
                Image(systemName: shouldStopSpeakToAppend ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        shouldStopSpeakToAppend ? AppColors.recording : AppColors.textSecondary
                    )
            }
        }
        .buttonStyle(.plain)
        .help(
            shouldStopSpeakToAppend
                ? localized("Stop listening", locale: locale)
                : localized("Speak to append", locale: locale)
        )
        .accessibilityLabel(
            shouldStopSpeakToAppend
                ? localized("Stop listening", locale: locale)
                : localized("Speak to append", locale: locale)
        )
    }

    // MARK: - Editor content

    /// The editor's text column starts after the heading-marker margin so the
    /// title, tags, and body text share one left edge (Granola-style gutter).
    private let textColumnInset: CGFloat = MarkdownTextView.headingMarginWidth

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(localized("Note Title", locale: locale), text: $title)
                .font(FontLoader.font(family: .newsreader, size: 28, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .textFieldStyle(.plain)
                .focused($titleFieldFocused)
                .padding(.leading, textColumnInset)
                .onSubmit {
                    contentFieldFocused = true
                }

            tagsRow
                .padding(.leading, textColumnInset)

            MarkdownEditor(text: $content)
                .accessibilityIdentifier("note-editor-body")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !generatedCitations.isEmpty {
                citationPanel
                    .padding(.leading, textColumnInset)
            }
        }

        .disabled(isAppendLocked)
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 8)
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

                    TextField(localized("Add tag", locale: locale), text: $newTag)
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

    private var citationPanel: some View {
        GroupBox {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(localized("Note", locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textTertiary)

                        Text(humanAnchorPresentationText)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    ForEach(Array(generatedCitations.enumerated()), id: \.offset) { _, citation in
                        Text(MeetingNoteDerivation.citationPresentationLine(citation))
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 104)
        } label: {
            Label(
                localized("Sources", locale: locale),
                systemImage: "checkmark.shield.fill"
            )
            .font(.headline)
            .foregroundStyle(AppColors.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.accentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.accent.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("note-editor-citation-panel")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(citationAccessibilityLabel)
    }

    private var humanAnchorPresentationText: String {
        MeetingNoteDerivation.sourcePresentationText(generatedHumanAnchorContent)
    }

    private var citationAccessibilityLabel: String {
        let sourceLines = generatedCitations
            .map(MeetingNoteDerivation.citationPresentationLine)
            .joined(separator: " ")
        return "\(localized("Sources", locale: locale)). \(localized("Note", locale: locale)): \(humanAnchorPresentationText). \(sourceLines)"
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
        }
        .padding(.horizontal, 40)
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
        if shouldStopSpeakToAppend {
            requestSpeakToAppendStop()
        } else {
            requestSpeakToAppendStart()
        }
    }

    /// Synchronously claims local ownership before its asynchronous preflight,
    /// preventing any post-Start draft mutation from racing the append commit.
    private func requestSpeakToAppendStart() {
        guard appendRequestState.requestedNoteID == nil,
              let noteToSave = currentNote
        else {
            return
        }

        let modelID = noteToSave.persistentModelID
        let noteID = noteToSave.id
        let container = modelContext.container
        appendRequestState.requestStart(noteID: noteID)
        autosaveTask?.cancel()
        autosaveTask = nil

        appendStartPreflightTask = Task { @MainActor in
            defer {
                appendStartPreflightTask = nil
            }

            while !Task.isCancelled {
                guard let currentNote,
                      currentNote.persistentModelID == modelID,
                      currentNote.id == noteID,
                      appendRequestState.isLocked(for: noteID)
                else {
                    return
                }

                let snapshot = currentSnapshot()
                let editedAt = lastEditedAt
                lastSavedSnapshot = snapshot

                let result = await NoteEditorPersistenceController.shared.saveAndWait(
                    container: container,
                    modelID: modelID,
                    snapshot: snapshot,
                    editedAt: editedAt
                )

                guard !Task.isCancelled else { return }
                guard appendRequestState.isLocked(for: noteID),
                      currentSnapshot() == snapshot
                else {
                    continue
                }
                guard let result,
                      result.applied,
                      result.generation == NoteEditorPersistenceController.shared.currentGeneration(for: modelID)
                else {
                    if lastSavedSnapshot == snapshot {
                        lastSavedSnapshot = nil
                    }
                    appendRequestState.clearAfterCommittedDelivery(noteID: noteID)
                    return
                }

                await handlePersistenceResult(
                    result,
                    modelID: modelID,
                    noteToSave: currentNote,
                    snapshot: snapshot,
                    editedAt: editedAt
                )

                guard appendRequestState.isLocked(for: noteID),
                      currentSnapshot() == snapshot,
                      currentNote.id == noteID
                else {
                    continue
                }

                NoteAppendListeningCoordinator.shared.requestStart(
                    editorID: editorID,
                    noteID: noteID
                )
                return
            }
        }
    }

    /// Cancels deferred work and posts Stop only after the exact current
    /// snapshot has been durably saved.
    private func requestSpeakToAppendStop() {
        guard let noteToSave = currentNote,
              let noteID = appendRequestState.requestedNoteID
                ?? (isThisEditorListening ? currentNote?.id : nil)
        else {
            return
        }

        appendStartPreflightTask?.cancel()
        appendStartPreflightTask = nil
        autosaveTask?.cancel()
        autosaveTask = nil

        let modelID = noteToSave.persistentModelID
        let container = modelContext.container
        appendStopFlushTask?.cancel()
        appendStopFlushTask = Task { @MainActor in
            defer {
                appendStopFlushTask = nil
            }

            while !Task.isCancelled {
                guard let currentNote,
                      currentNote.persistentModelID == modelID,
                      currentNote.id == noteID,
                      appendRequestState.isLocked(for: noteID) || isThisEditorListening
                else {
                    return
                }

                let snapshot = currentSnapshot()
                let editedAt = lastEditedAt
                lastSavedSnapshot = snapshot
                let result = await NoteEditorPersistenceController.shared.saveAndWait(
                    container: container,
                    modelID: modelID,
                    snapshot: snapshot,
                    editedAt: editedAt
                )

                guard !Task.isCancelled else { return }
                guard currentSnapshot() == snapshot else { continue }
                guard let result,
                      result.applied,
                      result.generation == NoteEditorPersistenceController.shared.currentGeneration(for: modelID)
                else {
                    if lastSavedSnapshot == snapshot {
                        lastSavedSnapshot = nil
                    }
                    return
                }

                await handlePersistenceResult(
                    result,
                    modelID: modelID,
                    noteToSave: currentNote,
                    snapshot: snapshot,
                    editedAt: editedAt
                )

                guard currentSnapshot() == snapshot,
                      currentNote.id == noteID
                else {
                    continue
                }

                NoteAppendListeningCoordinator.shared.requestStop(
                    editorID: editorID,
                    noteID: noteID
                )
                return
            }
        }
    }

    /// Reads citations only after validating the durable generated-note provenance.
    ///
    /// Both guards make a lookup harmless when an editor is replaced or a newer
    /// draft arrives while a save completion is being handled.
    private func loadMeetingCitations(
        for noteID: UUID?,
        expectedContent: String? = nil
    ) {
        guard let noteID,
              currentNote?.id == noteID,
              expectedContent.map({ content == $0 }) ?? true
        else {
            return
        }

        let validationGeneration = citationValidationGeneration
        let generatedNote: MeetingGeneratedNoteSnapshot?
        do {
            let store = CaptureSessionStore(modelContext: modelContext)
            generatedNote = try store.generatedMeetingNote(noteID: noteID)
        } catch {
            Log.app.error("Generated note citation metadata is invalid.")
            generatedNote = nil
        }

        guard citationValidationGeneration == validationGeneration,
              currentNote?.id == noteID,
              expectedContent.map({ content == $0 }) ?? true
        else {
            return
        }
        generatedCitations = generatedNote?.citations ?? []
        generatedHumanAnchorContent = generatedNote?.humanAnchorContent ?? ""
    }

    private func loadNoteData() {
        if let note = note {
            title = note.title
            content = note.content
            isPinned = note.isPinned
            tags = note.tags
            lastEditedAt = note.updatedAt
            currentNote = note
            lastSavedSnapshot = NoteSnapshot(note: note)
            displayedWordCount = note.content.wordCount
            loadMeetingCitations(for: note.id, expectedContent: note.content)
        } else {
            invalidateCitationValidation(clearingCitations: true)
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

    private func applyCommittedAppend(_ notification: Notification) {
        guard let payload = NoteAppendCommittedPayload(notification: notification),
              let currentNote
        else {
            return
        }

        let isAlreadyCommitted = content == payload.content
            && currentNote.sourceTranscriptionID == payload.sourceTranscriptionID
        guard payload.apply(to: currentNote, for: editorID) else { return }

        appendRequestState.clearAfterCommittedDelivery(noteID: payload.noteID)
        guard !isAlreadyCommitted else { return }

        // Record the committed durable body before changing the binding so the
        // binding observer cannot queue an autosave over the coordinator write.
        lastSavedSnapshot = NoteSnapshot(
            title: title.isEmpty ? "Untitled Note" : title,
            content: payload.content,
            isPinned: isPinned,
            tags: tags
        )
        content = payload.content
        onSave(currentNote)
    }

    private func clearAppendRequestAfterSessionFinish() {
        appendRequestState.clearAfterSessionFinishes(
            isListening: appendSessionState.isListening,
            isProcessing: appendSessionState.isProcessing,
            activeEditorID: appendSessionState.activeEditorID,
            activeNoteID: appendSessionState.activeNoteID
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
              result.generation == NoteEditorPersistenceController.shared.currentGeneration(for: modelID),
              currentNote?.persistentModelID == modelID,
              currentNote?.id == noteToSave.id,
              currentSnapshot() == snapshot
        else {
            return
        }

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

        // Citations are trusted only when a fresh store validation confirms the
        // exact persisted note still has valid generated-note provenance.
        loadMeetingCitations(for: noteToSave.id, expectedContent: snapshot.content)
    }

    private func saveNow() {
        // The preflight/stop paths own durable snapshots while appending; a
        // concurrent manual save could otherwise overwrite the committed append.
        guard !isAppendLocked else { return }

        autosaveTask?.cancel()
        saveNote(immediate: true)
        showSavedFlash()
    }

    private func noteDidChange() {
        let snapshot = currentSnapshot()
        // A committed append sets this first, so its binding update cannot queue
        // an autosave that races the coordinator's direct store commit.
        guard snapshot != lastSavedSnapshot else { return }

        lastEditedAt = Date()
        // Capture the latest draft synchronously before the 500ms debounce so quit
        // can persist mid-debounce edits without relying on onDisappear timing.
        if let noteToSave = currentNote {
            NoteEditorPersistenceController.shared.trackDraft(
                container: modelContext.container,
                modelID: noteToSave.persistentModelID,
                snapshot: snapshot,
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

    /// Clears trusted citation metadata synchronously when an edited title or
    /// body contains a reserved citation form or another value the generated-note
    /// sanitizer would change. Sanitized edits remain eligible for store revalidation.
    private func invalidateCitationValidation(
        body: String? = nil,
        title: String? = nil,
        clearingCitations: Bool = false
    ) {
        citationValidationGeneration &+= 1
        let body = body ?? content
        let title = title ?? self.title
        if clearingCitations
            || !Self.permitsTrustedCitations(in: body)
            || title != MeetingNoteDerivation.sanitizingGeneratedContent(title) {
            generatedCitations = []
            generatedHumanAnchorContent = ""
        }
    }

    static func permitsTrustedCitations(in body: String) -> Bool {
        body == MeetingNoteDerivation.sanitizingGeneratedContent(body)
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
    @Published private(set) var activeNoteID: UUID?

    fileprivate func apply(
        isListening: Bool,
        isProcessing: Bool,
        activeEditorID: UUID?,
        activeNoteID: UUID?
    ) {
        if self.isListening != isListening { self.isListening = isListening }
        if self.isProcessing != isProcessing { self.isProcessing = isProcessing }
        if self.activeEditorID != activeEditorID { self.activeEditorID = activeEditorID }
        if self.activeNoteID != activeNoteID { self.activeNoteID = activeNoteID }
    }
}

@MainActor
final class NoteAppendListeningCoordinatorBox {
    let state = NoteAppendListeningState()
    /// Lightweight mirror of ownership/processing for the editor root (no elapsed).
    let sessionState = NoteAppendSessionState()

    private var sessionStateCancellable: AnyCancellable?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        // All source mutations are main-actor isolated, so mirror synchronously.
        // Scheduling onto RunLoop.main introduced a stale-state window between a
        // session transition and the editor deciding whether Start or Stop applies.
        sessionStateCancellable = state.$isListening
            .combineLatest(state.$isProcessing, state.$activeEditorID, state.$activeNoteID)
            .sink { [weak self] isListening, isProcessing, activeEditorID, activeNoteID in
                guard let self else { return }
                self.sessionState.apply(
                    isListening: isListening,
                    isProcessing: isProcessing,
                    activeEditorID: activeEditorID,
                    activeNoteID: activeNoteID
                )
            }
    }

    deinit {
        sessionStateCancellable?.cancel()
    }

    func requestStart(editorID: UUID, noteID: UUID) {
        notificationCenter.post(
            name: .noteSpeakToAppendRequest,
            object: nil,
            userInfo: [
                "editorID": editorID,
                "noteID": noteID,
                "action": "start"
            ]
        )
    }

    func requestStop(editorID: UUID, noteID: UUID) {
        notificationCenter.post(
            name: .noteSpeakToAppendRequest,
            object: nil,
            userInfo: [
                "editorID": editorID,
                "noteID": noteID,
                "action": "stop"
            ]
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
                // A chip is one line and sizes to its word; a narrow row must
                // not break a word across two lines.
                .lineLimit(1)
                .fixedSize()

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
    .frame(width: 680, height: 760)
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
    .frame(width: 680, height: 760)
    .modelContainer(container)
}
