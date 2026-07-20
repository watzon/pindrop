//
//  DictionaryView.swift
//  Pindrop
//
//  Dictionary page (U6 scorched-earth restyle, spec §11).
//

import SwiftUI
import SwiftData
import Foundation
import AppKit

// MARK: - Async lifecycle (pure seams)

/// Pure commit/selection rules for Dictionary import, export, and load.
/// Detached file I/O is not cooperatively cancelled; callers must re-check
/// generation after `Task.detached` returns before mutating view state.
enum DictionaryAsyncLifecycle {
    /// `true` only when this request is still the active generation and not cancelled.
    static func canCommit(
        generation: UInt,
        activeGeneration: UInt,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && generation == activeGeneration
    }

    /// Derive keyboard-selection IDs and reconcile the current selection against them.
    /// Call only after both collections have been fetched/sorted into locals so a
    /// partial failure cannot leave arrays and IDs divergent.
    static func makeLoadCommit(
        replacementIDs: [UUID],
        vocabularyIDs: [UUID],
        selectedRowID: UUID?
    ) -> (selectableIDs: [UUID], selectedRowID: UUID?) {
        let selectableIDs = replacementIDs + vocabularyIDs
        let reconciled: UUID?
        if let selectedRowID, selectableIDs.contains(selectedRowID) {
            reconciled = selectedRowID
        } else {
            reconciled = nil
        }
        return (selectableIDs, reconciled)
    }

    /// After a durable export finishes: deliver immediately when a Dictionary page
    /// is live; otherwise retain until a sink is next installed. Unrelated success
    /// must not discard retained failures.
    enum ExportFailureDisposition: Equatable {
        case deliverImmediately
        case retainPending
    }

    static func exportFailureDisposition(hasLiveSink: Bool) -> ExportFailureDisposition {
        hasLiveSink ? .deliverImmediately : .retainPending
    }

    /// Success only clears retained failures that targeted the same destination URL.
    static func retainedFailuresAfterSuccess(
        pendingDestinations: [URL],
        succeededDestination: URL
    ) -> [URL] {
        pendingDestinations.filter { $0 != succeededDestination }
    }

    /// Local CRUD/import errors and durable export failures share no identity.
    /// Only dismissing an export surface advances the export failure queue.
    enum ErrorSurface: Equatable {
        case local
        case export
    }

    static func shouldAdvanceExportQueue(dismissedSurface: ErrorSurface) -> Bool {
        dismissedSurface == .export
    }
}

/// Owns serialized dictionary exports outside the view lifetime so a user-chosen
/// save continues after page navigation. Failures that finish while no Dictionary
/// page is live are retained and delivered when a sink is next installed.
/// Unrelated successful exports never discard retained failures for other destinations.
@MainActor
private final class DictionaryExportWorkOwner {
    static let shared = DictionaryExportWorkOwner()

    private struct PendingFailure {
        let destination: URL
        let error: Error
    }

    private var generation: UInt = 0
    private var task: Task<Void, Never>?
    private var errorSink: ((Error) -> Void)?
    private var pendingFailures: [PendingFailure] = []
    private var presentedFailure: PendingFailure?

    /// Install (or replace) the live Dictionary page's error presenter.
    /// Immediately delivers any failures that completed while no sink was live.
    func installErrorSink(_ sink: @escaping (Error) -> Void) {
        errorSink = sink
        flushPendingFailures()
    }

    /// Drop presentation for the departing page without cancelling writes or
    /// discarding failures that still need to be shown.
    func clearErrorSink() {
        errorSink = nil
        if let presentedFailure {
            pendingFailures.removeAll { $0.destination == presentedFailure.destination }
            pendingFailures.insert(presentedFailure, at: 0)
            self.presentedFailure = nil
        }
    }

    /// Marks the currently presented failure as dismissed. Does **not** flush the
    /// next item synchronously — the view must allow `isPresented` to go false for
    /// a render turn, then call `deliverNextPendingFailureIfNeeded()`.
    func acknowledgePresentedFailure() {
        presentedFailure = nil
    }

    /// Deliver the next retained failure after the previous alert fully dismissed.
    func deliverNextPendingFailureIfNeeded() {
        flushPendingFailures()
    }

    /// Enqueue an atomic export. Prior work always finishes first; this request's
    /// write is never cancelled by view disappearance.
    func enqueue(
        data: Data,
        url: URL,
        didStartAccess: Bool
    ) {
        generation &+= 1
        let generation = self.generation
        let previous = task

        task = Task { @MainActor in
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                if generation == self.generation {
                    self.task = nil
                }
            }

            // Drain prior exports so same-destination writes cannot reorder.
            await previous?.value

            do {
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: url, options: [.atomic])
                }.value
                // Only supersede retained failures for this same destination.
                // Unrelated destinations stay queued until delivered.
                pendingFailures.removeAll { $0.destination == url }
            } catch is CancellationError {
                // Export is intentionally non-cancellable from view lifecycle.
                return
            } catch {
                presentOrRetain(error, destination: url)
            }
        }
    }

    private func presentOrRetain(_ error: Error, destination: URL) {
        let failure = PendingFailure(destination: destination, error: error)
        pendingFailures.removeAll { $0.destination == destination }

        guard let errorSink, presentedFailure == nil else {
            pendingFailures.append(failure)
            return
        }

        presentedFailure = failure
        errorSink(error)
    }

    private func flushPendingFailures() {
        guard
            let errorSink,
            presentedFailure == nil,
            !pendingFailures.isEmpty
        else {
            return
        }

        let failure = pendingFailures.removeFirst()
        presentedFailure = failure
        errorSink(failure.error)
    }
}

struct DictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @State private var dictionaryStore: DictionaryStore?
    /// Ordered display arrays established only when data mutates (load/add/edit/delete/reorder/import).
    @State private var replacements: [WordReplacement] = []
    @State private var vocabularyWords: [VocabularyWord] = []
    @State private var selectableIDs: [UUID] = []

    // Presentation-only sheet identity (draft fields live in sheet children).
    @State private var showAddWordSheet = false
    @State private var showAddReplacementSheet = false
    @State private var editingReplacement: WordReplacement?
    @State private var editingVocabulary: VocabularyWord?

    @State private var errorMessage: String?
    /// Separate from local CRUD/import errors so export-queue advancement never
    /// fires for non-export alerts, and so successive export alerts can re-present.
    @State private var exportErrorMessage: String = ""
    @State private var isExportErrorPresented = false
    /// Bumped each time an export failure is presented; late dismissals for an
    /// older presentation cannot acknowledge or clear a newer one.
    @State private var exportAlertPresentationGeneration: UInt = 0
    @State private var showingImportStrategyDialog = false
    @State private var importDataCache: Data?
    @State private var importTask: Task<Void, Never>?
    @State private var importGeneration: UInt = 0
    // Export write ownership lives on DictionaryExportWorkOwner; no view-local export task.

    @State private var selectedRowID: UUID?
    @State private var addEntryMenuAnchorView: NSView?
    @State private var keyMonitor: Any?
    private var isCompletelyEmpty: Bool {
        replacements.isEmpty && vocabularyWords.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 18)
                .background(AppColors.contentBackground)

            // One List is the sole vertical scroller so replacement rows
            // virtualize instead of expanding to full content height.
            List {
                if isCompletelyEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    vocabularySection
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    SectionHeader(
                        title: localized("Replacements", locale: locale),
                        trailing: localized("Applied after transcription, before insert", locale: locale),
                        isFirst: false
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if replacements.isEmpty {
                        Text(localized("No Replacements", locale: locale))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(replacements) { replacement in
                            replacementRow(replacement)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveReplacements)
                    }

                    footnote
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Color.clear
                    .frame(height: 32)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)
            .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
        .onAppear {
            dictionaryStore = DictionaryStore(modelContext: modelContext)
            loadData()
            installKeyMonitorIfNeeded()
            DictionaryExportWorkOwner.shared.installErrorSink { [locale] error in
                presentExportError(
                    localized("Failed to export dictionary: %@", locale: locale)
                        .replacingOccurrences(of: "%@", with: error.localizedDescription)
                )
            }
        }
        .onDisappear {
            removeKeyMonitor()
            cancelManagedImportWork()
            DictionaryExportWorkOwner.shared.clearErrorSink()
            isExportErrorPresented = false
            exportErrorMessage = ""
        }
        .alert(
            localized("Import Error", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK", locale: locale)) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .alert(
            localized("Import Error", locale: locale),
            isPresented: $isExportErrorPresented
        ) {
            Button(localized("OK", locale: locale)) {
                // Only flip presentation. Queue advancement runs exclusively from
                // the confirmed isPresented true→false transition below.
                isExportErrorPresented = false
            }
        } message: {
            Text(exportErrorMessage)
        }
        .onChange(of: isExportErrorPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            handleConfirmedExportAlertDismissal()
        }
        .confirmationDialog(localized("Import Strategy", locale: locale), isPresented: $showingImportStrategyDialog) {
            Button(localized("Add to Existing", locale: locale)) {
                performImport(strategy: .additive)
            }
            Button(localized("Replace All", locale: locale), role: .destructive) {
                performImport(strategy: .replace)
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(localized("Choose how to import the dictionary data", locale: locale))
        }
        .sheet(isPresented: $showAddWordSheet) {
            DictionaryAddWordSheet(locale: locale) { word in
                handleAddWord(word)
            }
        }
        .sheet(isPresented: $showAddReplacementSheet) {
            DictionaryAddReplacementSheet(locale: locale) { originals, replacement, matchMode in
                handleAddReplacement(
                    originals: originals,
                    replacement: replacement,
                    matchMode: matchMode
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { editingVocabulary != nil },
            set: { if !$0 { editingVocabulary = nil } }
        )) {
            if let word = editingVocabulary {
                DictionaryEditVocabularySheet(
                    locale: locale,
                    initialWord: word.word
                ) { updated in
                    saveVocabularyEdit(word, newWord: updated)
                } onCancel: {
                    editingVocabulary = nil
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingReplacement != nil },
            set: { if !$0 { editingReplacement = nil } }
        )) {
            if let replacement = editingReplacement {
                DictionaryEditReplacementSheet(
                    locale: locale,
                    initialOriginals: replacement.originals.joined(separator: ", "),
                    initialReplacement: replacement.replacement,
                    initialMatchMode: replacement.matchMode
                ) { originals, value, matchMode in
                    saveReplacementEdit(
                        replacement,
                        originals: originals,
                        replacement: value,
                        matchMode: matchMode
                    )
                } onCancel: {
                    editingReplacement = nil
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        PageHeader(
            title: localized("Dictionary", locale: locale),
            meta: localized("Teach Pindrop your words", locale: locale)
        ) {
            addEntryControl
        }
    }

    /// Matches the Library page's true split-button behavior: the main segment
    /// adds a word, while the chevron exposes every secondary dictionary action.
    private var addEntryControl: some View {
        HStack(spacing: 0) {
            Button {
                showAddWordSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(localized("Add word", locale: locale))
                        .font(AppTypography.labelSemibold)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized("Add word", locale: locale))

            Rectangle()
                .fill(AppColors.contentBackground.opacity(0.35))
                .frame(width: 1, height: 16)

            Button {
                presentAddEntryMenu()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(localized("Add replacement", locale: locale)), \(localized("Import/Export", locale: locale))"
            )
            .help(localized("Import/Export", locale: locale))
        }
        .foregroundStyle(AppColors.contentBackground)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.accent)
        )
        .background(
            DictionaryMenuAnchor { view in
                addEntryMenuAnchorView = view
            }
        )
        .fixedSize()
    }

    private func presentAddEntryMenu() {
        guard let anchor = addEntryMenuAnchorView else { return }

        let menu = NSMenu()
        menu.addItem(DictionaryActionMenuItem(
            title: localized("Add replacement", locale: locale),
            systemImage: "arrow.left.arrow.right"
        ) {
            showAddReplacementSheet = true
        })
        menu.addItem(.separator())
        menu.addItem(DictionaryActionMenuItem(
            title: localized("Import Dictionary", locale: locale),
            systemImage: "square.and.arrow.down",
            handler: handleImport
        ))
        menu.addItem(DictionaryActionMenuItem(
            title: localized("Export Dictionary", locale: locale),
            systemImage: "square.and.arrow.up",
            handler: handleExport
        ))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: anchor)
    }

    // MARK: - Vocabulary section

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: localized("Vocabulary", locale: locale),
                trailing: localized("Words the recognizer should trust", locale: locale),
                isFirst: true
            )
            .padding(.horizontal, 20)

            FlowLayout(spacing: 8) {
                ForEach(vocabularyWords) { word in
                    vocabularyChip(word)
                }
                addVocabularyChip
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func vocabularyChip(_ word: VocabularyWord) -> some View {
        let isSelected = selectedRowID == word.id
        return Button {
            selectedRowID = word.id
        } label: {
            HStack(spacing: 7) {
                Text(word.word)
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(word.usageCount)")
                    .font(FontLoader.font(family: .jetbrainsMono, size: 10, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(AppColors.windowBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? AppColors.accent.opacity(0.55) : AppColors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(Capsule(style: .continuous))
        .overlay {
            VocabularyContextMenuPresenter(
                editTitle: localized("Edit", locale: locale),
                deleteTitle: localized("Delete", locale: locale),
                onOpen: {
                    selectedRowID = word.id
                },
                onEdit: {
                    startEditingVocabulary(word)
                },
                onDelete: {
                    deleteVocabularyWord(id: word.id)
                }
            )
            .accessibilityHidden(true)
        }
        .accessibilityAction(named: localized("Edit", locale: locale)) {
            startEditingVocabulary(word)
        }
        .accessibilityAction(named: localized("Delete", locale: locale)) {
            deleteVocabularyWord(id: word.id)
        }
        .onTapGesture(count: 2) {
            startEditingVocabulary(word)
        }
    }

    private var addVocabularyChip: some View {
        Button {
            showAddWordSheet = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                Text(localized("Add", locale: locale))
                    .font(AppTypography.labelStrong)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .overlay(
                Capsule()
                    .strokeBorder(
                        AppColors.border,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardFocusRing(Capsule(style: .continuous))
    }

    // MARK: - Replacement rows

    private func replacementRow(_ replacement: WordReplacement) -> some View {
        let isSelected = selectedRowID == replacement.id
        let pattern = DictionaryCommandTokenDisplay.patternDisplay(originals: replacement.originals)
        let value = DictionaryCommandTokenDisplay.replacementDisplay(
            replacement: replacement.replacement,
            matchMode: replacement.matchMode
        )
        let modeLabel = DictionaryMatchModeLabel.label(for: replacement.matchMode, locale: locale)

        return Button {
            selectedRowID = replacement.id
        } label: {
            HStack(spacing: 14) {
                Text(pattern)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 14, height: 14)
                    .flipsForRightToLeftLayoutDirection(true)

                Text(value)
                    .font(FontLoader.font(family: .jetbrainsMono, size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(modeLabel)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
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
        .contextMenu {
            Button {
                startEditingReplacement(replacement)
            } label: {
                Label(localized("Edit", locale: locale), systemImage: "pencil")
            }
            Menu(localized("Match mode", locale: locale)) {
                ForEach([ReplacementMatchMode.caseInsensitive, .exact, .command], id: \.rawValue) { mode in
                    Button {
                        setMatchMode(replacement, mode: mode)
                    } label: {
                        if replacement.matchMode == mode {
                            Label(DictionaryMatchModeLabel.label(for: mode, locale: locale), systemImage: "checkmark")
                        } else {
                            Text(DictionaryMatchModeLabel.label(for: mode, locale: locale))
                        }
                    }
                }
            }
            Button(role: .destructive) {
                deleteReplacement(replacement)
            } label: {
                Label(localized("Delete", locale: locale), systemImage: "trash")
            }
        }
        .onTapGesture(count: 2) {
            startEditingReplacement(replacement)
        }
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
            Text(localized("Replacements run in order. Drag rows to re-order — the first match wins.", locale: locale))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("No dictionary entries", locale: locale))
                .font(AppTypography.labelStrong)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Add words the recognizer should trust, or replacements applied after transcription.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            PrimaryButton(
                title: localized("Add word", locale: locale),
                systemImage: "plus",
                action: {
                    showAddWordSheet = true
                }
            )
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func handleAddWord(_ trimmed: String) {
        guard let store = dictionaryStore else { return }
        guard !trimmed.isEmpty else { return }
        guard !vocabularyWords.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) else {
            return
        }
        do {
            try store.add(VocabularyWord(word: trimmed))
            loadData()
        } catch {
            errorMessage = localized("Failed to add word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func handleAddReplacement(
        originals: [String],
        replacement: String,
        matchMode: ReplacementMatchMode
    ) {
        guard let store = dictionaryStore else { return }
        guard !originals.isEmpty else { return }
        do {
            let model = WordReplacement(
                originals: originals,
                replacement: replacement,
                sortOrder: replacements.count,
                matchModeRawValue: matchMode.rawValue
            )
            try store.add(model)
            loadData()
        } catch {
            errorMessage = localized("Failed to add replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func startEditingReplacement(_ replacement: WordReplacement) {
        editingReplacement = replacement
    }

    private func startEditingVocabulary(_ word: VocabularyWord) {
        editingVocabulary = word
    }

    private func saveReplacementEdit(
        _ replacement: WordReplacement,
        originals: [String],
        replacement value: String,
        matchMode: ReplacementMatchMode
    ) {
        guard let store = dictionaryStore else { return }
        guard !originals.isEmpty else {
            editingReplacement = nil
            return
        }
        do {
            replacement.originals = originals
            replacement.replacement = value
            replacement.matchModeRawValue = matchMode.rawValue
            try store.saveContext()
            editingReplacement = nil
            loadData()
        } catch {
            errorMessage = localized("Failed to update replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func saveVocabularyEdit(_ word: VocabularyWord, newWord: String) {
        guard let store = dictionaryStore else { return }
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingVocabulary = nil
            return
        }
        let isDuplicate = vocabularyWords.contains {
            $0.id != word.id && $0.word.lowercased() == trimmed.lowercased()
        }
        guard !isDuplicate else {
            editingVocabulary = nil
            return
        }
        do {
            word.word = trimmed
            try store.saveContext()
            editingVocabulary = nil
            loadData()
        } catch {
            errorMessage = localized("Failed to update word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func setMatchMode(_ replacement: WordReplacement, mode: ReplacementMatchMode) {
        guard let store = dictionaryStore else { return }
        do {
            replacement.matchModeRawValue = mode.rawValue
            try store.saveContext()
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveReplacements(from source: IndexSet, to destination: Int) {
        guard let store = dictionaryStore else { return }
        do {
            try store.reorder(replacements, from: source, to: destination)
            loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteReplacement(_ replacement: WordReplacement) {
        guard let store = dictionaryStore else { return }
        do {
            try store.delete(replacement)
            if selectedRowID == replacement.id { selectedRowID = nil }
            loadData()
        } catch {
            errorMessage = localized("Failed to delete replacement: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func deleteVocabularyWord(_ word: VocabularyWord) {
        guard let store = dictionaryStore else { return }
        do {
            try store.delete(word)
            if selectedRowID == word.id { selectedRowID = nil }
            loadData()
        } catch {
            errorMessage = localized("Failed to delete word: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func deleteVocabularyWord(id: UUID) {
        guard let word = vocabularyWords.first(where: { $0.id == id }) else { return }
        deleteVocabularyWord(word)
    }

    private func loadData() {
        guard let store = dictionaryStore else { return }
        do {
            // Fetch/sort both collections into locals first so a mid-load throw
            // cannot leave replacements, vocabulary, and selectableIDs divergent.
            let fetchedReplacements = try store.fetchAllReplacements()
            let sortedReplacements = fetchedReplacements.sorted(by: { $0.sortOrder < $1.sortOrder })

            let fetchedVocabulary = try store.fetchAllVocabularyWords()
            let sortedVocabulary = DictionaryVocabularyOrdering.sortedModels(fetchedVocabulary)

            let commit = DictionaryAsyncLifecycle.makeLoadCommit(
                replacementIDs: sortedReplacements.map(\.id),
                vocabularyIDs: sortedVocabulary.map(\.id),
                selectedRowID: selectedRowID
            )

            replacements = sortedReplacements
            vocabularyWords = sortedVocabulary
            selectableIDs = commit.selectableIDs
            selectedRowID = commit.selectedRowID
        } catch {
            errorMessage = localized("Failed to load data: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func handleExport() {
        guard let store = dictionaryStore else { return }
        let currentLocale = locale
        do {
            // SwiftData export stays on the main actor; only the disk write moves off.
            let jsonData = try store.exportToJSON()
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "dictionary.json"
            savePanel.title = localized("Export Dictionary", locale: currentLocale)
            savePanel.message = localized("Choose a location to save the dictionary", locale: currentLocale)
            guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

            // Security-scoped access must begin on the main actor before the detached write.
            // Ownership is process-wide so navigation cannot drop a user-chosen save.
            let didStartAccess = url.startAccessingSecurityScopedResource()
            DictionaryExportWorkOwner.shared.enqueue(
                data: jsonData,
                url: url,
                didStartAccess: didStartAccess
            )
        } catch {
            errorMessage = localized("Failed to export dictionary: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    private func handleImport() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        let currentLocale = locale
        openPanel.title = localized("Import Dictionary", locale: currentLocale)
        openPanel.message = localized("Select a dictionary JSON file to import", locale: currentLocale)
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        // New selection invalidates any in-flight import and any pending confirmation.
        importGeneration &+= 1
        let generation = importGeneration
        importTask?.cancel()
        importDataCache = nil
        showingImportStrategyDialog = false

        // Security-scoped access must begin on the main actor before the detached read.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        importTask = Task { @MainActor in
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
                if generation == importGeneration {
                    importTask = nil
                }
            }

            do {
                // Detached work is not cooperatively cancelled by parent cancellation;
                // generation must be re-checked after the await before committing.
                let data = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url)
                    _ = try JSONDecoder().decode(DictionaryImportPreview.self, from: data)
                    return data
                }.value

                guard DictionaryAsyncLifecycle.canCommit(
                    generation: generation,
                    activeGeneration: importGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }

                importDataCache = data
                showingImportStrategyDialog = true
            } catch is CancellationError {
                return
            } catch {
                guard DictionaryAsyncLifecycle.canCommit(
                    generation: generation,
                    activeGeneration: importGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                errorMessage = localized("Failed to read import file: %@", locale: currentLocale)
                    .replacingOccurrences(of: "%@", with: error.localizedDescription)
            }
        }
    }

    /// Invalidates in-flight import presentation only. Export writes are durable
    /// and must not be cancelled when this page disappears.
    private func cancelManagedImportWork() {
        importGeneration &+= 1
        importTask?.cancel()
        importTask = nil
        importDataCache = nil
        showingImportStrategyDialog = false
    }

    /// Present a durable export failure on the dedicated export surface.
    private func presentExportError(_ message: String) {
        exportAlertPresentationGeneration &+= 1
        exportErrorMessage = message
        isExportErrorPresented = true
    }

    /// Confirmed export-alert dismissal (`isPresented` true → false). Acknowledge
    /// the presented failure, then schedule the next delivery after this callback
    /// returns — never from the OK action, and never via Task.yield-as-barrier.
    private func handleConfirmedExportAlertDismissal() {
        guard DictionaryAsyncLifecycle.shouldAdvanceExportQueue(dismissedSurface: .export) else {
            exportErrorMessage = ""
            return
        }

        let dismissedGeneration = exportAlertPresentationGeneration
        exportErrorMessage = ""
        DictionaryExportWorkOwner.shared.acknowledgePresentedFailure()

        // After this onChange callback returns, isPresented is already false.
        // A later main-actor turn may present the next queued failure without
        // racing the dismissal that just completed.
        Task { @MainActor in
            guard dismissedGeneration == exportAlertPresentationGeneration else { return }
            guard !isExportErrorPresented else { return }
            DictionaryExportWorkOwner.shared.deliverNextPendingFailureIfNeeded()
        }
    }

    private func performImport(strategy: DictionaryStore.ImportStrategy) {
        guard let store = dictionaryStore, let data = importDataCache else { return }
        do {
            try store.importFromJSON(data, strategy: strategy)
            loadData()
            importDataCache = nil
        } catch {
            errorMessage = localized("Failed to import dictionary: %@", locale: locale)
                .replacingOccurrences(of: "%@", with: error.localizedDescription)
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.shouldHandleListKeyEvent(event) else { return event }
            if self.editingReplacement != nil || self.editingVocabulary != nil
                || self.showAddWordSheet || self.showAddReplacementSheet {
                return event
            }
            return self.handleListKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static func shouldHandleListKeyEvent(_ event: NSEvent) -> Bool {
        guard MainWindowController.isMainWindowKey(event.window) else { return false }
        if isTextInputFirstResponder(event.window?.firstResponder) {
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
            moveSelection(delta: -1)
            return nil
        case 125:
            moveSelection(delta: 1)
            return nil
        case 51, 117:
            deleteSelectedRow()
            return nil
        case 53:
            if selectedRowID != nil {
                selectedRowID = nil
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func moveSelection(delta: Int) {
        let ids = selectableIDs
        let currentIndex = ids.firstIndex(where: { $0 == selectedRowID })
        guard let nextIndex = ListSelectionNavigation.moveIndex(
            current: currentIndex,
            count: ids.count,
            delta: delta
        ) else { return }
        selectedRowID = ids[nextIndex]
    }

    private func deleteSelectedRow() {
        guard let selectedRowID else { return }
        if let replacement = replacements.first(where: { $0.id == selectedRowID }) {
            deleteReplacement(replacement)
            self.selectedRowID = nil
        } else if let word = vocabularyWords.first(where: { $0.id == selectedRowID }) {
            deleteVocabularyWord(word)
            self.selectedRowID = nil
        }
    }
}

// MARK: - Dictionary AppKit menu support

/// Exposes a stable anchor so the split-button menu aligns with the full control.
private struct DictionaryMenuAnchor: NSViewRepresentable {
    let onReady: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Owns its action because `NSMenuItem.target` is weak.
private final class DictionaryActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

/// Supplies an item-scoped AppKit context menu without letting the enclosing
/// `List` promote every vocabulary chip to one highlighted context-menu row.
private struct VocabularyContextMenuPresenter: NSViewRepresentable {
    let editTitle: String
    let deleteTitle: String
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> VocabularyContextMenuView {
        let view = VocabularyContextMenuView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: VocabularyContextMenuView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: VocabularyContextMenuView) {
        view.editTitle = editTitle
        view.deleteTitle = deleteTitle
        view.onOpen = onOpen
        view.onEdit = onEdit
        view.onDelete = onDelete
    }
}

private final class VocabularyContextMenuView: NSView {
    var editTitle = ""
    var deleteTitle = ""
    var onOpen: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point), let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown:
            return self
        case .leftMouseDown where event.modifierFlags.contains(.control):
            return self
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        presentMenu(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        presentMenu(with: event)
    }

    private func presentMenu(with event: NSEvent) {
        onOpen()

        let menu = NSMenu()
        menu.addItem(DictionaryActionMenuItem(
            title: editTitle,
            systemImage: "pencil",
            handler: onEdit
        ))
        menu.addItem(DictionaryActionMenuItem(
            title: deleteTitle,
            systemImage: "trash",
            handler: onDelete
        ))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - Sheet children (draft state local)

private struct DictionaryAddWordSheet: View {
    let locale: Locale
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var primaryInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Add word", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Enter word to add", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    dismiss()
                }
                PrimaryButton(
                    title: localized("Add", locale: locale),
                    isEnabled: !primaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: {
                        let trimmed = primaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(trimmed)
                        dismiss()
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(AppColors.contentBackground)
    }
}

private struct DictionaryAddReplacementSheet: View {
    let locale: Locale
    let onAdd: ([String], String, ReplacementMatchMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var primaryInput = ""
    @State private var secondaryInput = ""
    @State private var matchMode: ReplacementMatchMode = .caseInsensitive

    private var canAdd: Bool {
        !primaryInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !secondaryInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Add replacement", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Original text (use commas for multiple)", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            TextField(localized("Replacement text", locale: locale), text: $secondaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            Picker(localized("Match mode", locale: locale), selection: $matchMode) {
                Text(DictionaryMatchModeLabel.label(for: .caseInsensitive, locale: locale))
                    .tag(ReplacementMatchMode.caseInsensitive)
                Text(DictionaryMatchModeLabel.label(for: .exact, locale: locale))
                    .tag(ReplacementMatchMode.exact)
                Text(DictionaryMatchModeLabel.label(for: .command, locale: locale))
                    .tag(ReplacementMatchMode.command)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    dismiss()
                }
                PrimaryButton(
                    title: localized("Add", locale: locale),
                    isEnabled: canAdd,
                    action: {
                        let originals = primaryInput
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let replacementText = secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(originals, replacementText, matchMode)
                        dismiss()
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(AppColors.contentBackground)
    }
}

private struct DictionaryEditVocabularySheet: View {
    let locale: Locale
    let initialWord: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var primaryInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Edit", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Word", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    onCancel()
                }
                PrimaryButton(
                    title: localized("Save", locale: locale),
                    action: {
                        onSave(primaryInput)
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(AppColors.contentBackground)
        .onAppear {
            primaryInput = initialWord
        }
    }
}

private struct DictionaryEditReplacementSheet: View {
    let locale: Locale
    let initialOriginals: String
    let initialReplacement: String
    let initialMatchMode: ReplacementMatchMode
    let onSave: ([String], String, ReplacementMatchMode) -> Void
    let onCancel: () -> Void

    @State private var primaryInput = ""
    @State private var secondaryInput = ""
    @State private var matchMode: ReplacementMatchMode = .caseInsensitive

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Edit", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Originals (comma-separated)", locale: locale), text: $primaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            TextField(localized("Replacement", locale: locale), text: $secondaryInput)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            Picker(localized("Match mode", locale: locale), selection: $matchMode) {
                Text(DictionaryMatchModeLabel.label(for: .caseInsensitive, locale: locale))
                    .tag(ReplacementMatchMode.caseInsensitive)
                Text(DictionaryMatchModeLabel.label(for: .exact, locale: locale))
                    .tag(ReplacementMatchMode.exact)
                Text(DictionaryMatchModeLabel.label(for: .command, locale: locale))
                    .tag(ReplacementMatchMode.command)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                SecondaryButton(title: localized("Cancel", locale: locale)) {
                    onCancel()
                }
                PrimaryButton(
                    title: localized("Save", locale: locale),
                    action: {
                        let originals = primaryInput
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let value = secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(originals, value, matchMode)
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(AppColors.contentBackground)
        .onAppear {
            primaryInput = initialOriginals
            secondaryInput = initialReplacement
            matchMode = initialMatchMode
        }
    }
}

// MARK: - Dictionary Import Preview

struct DictionaryImportPreview: Codable {
    let version: Int
    let replacements: [ReplacementPreview]
    let vocabulary: [VocabularyPreview]

    struct ReplacementPreview: Codable {
        let originals: [String]
        let replacement: String
    }

    struct VocabularyPreview: Codable {
        let word: String
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct Cache {
        var sizes: [CGSize] = []
        var width: CGFloat?
        var result: FlowResult?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        if sizes != cache.sizes {
            cache.sizes = sizes
            cache.width = nil
            cache.result = nil
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 0
        if cache.sizes.count != subviews.count {
            cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            cache.width = nil
            cache.result = nil
        }
        if let cached = cache.result, cache.width == width {
            return cached.size
        }
        let result = FlowResult(in: width, sizes: cache.sizes, spacing: spacing)
        cache.width = width
        cache.result = result
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let width = bounds.width
        if cache.sizes.count != subviews.count {
            cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            cache.width = nil
            cache.result = nil
        }
        let result: FlowResult
        if let cached = cache.result, cache.width == width {
            result = cached
        } else {
            result = FlowResult(in: width, sizes: cache.sizes, spacing: spacing)
            cache.width = width
            cache.result = result
        }
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { continue }
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, sizes: [CGSize], spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for size in sizes {
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing

                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Preview

#Preview("Dictionary View - Empty") {
    DictionaryView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.light)
}
