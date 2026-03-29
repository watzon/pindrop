//
//  TranscribeView.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import AVFoundation
import AVKit
import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import PindropSharedUIWorkspace

struct TranscribeView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @Query private var mediaFolders: [MediaFolder]
    @Bindable var featureState: MediaTranscriptionFeatureState
    @Bindable var modelManager: ModelManager
    @ObservedObject var settingsStore: SettingsStore

    let onImportFiles: ([URL]) -> Void
    let onSubmitLink: (String) -> Void
    let onDownloadDiarizationModel: () -> Void
    let onOpenModels: (() -> Void)?

    @State private var isTargeted = false
    @State private var pendingDeletionRecord: TranscriptionRecord?
    @State private var pendingDeletionFolder: MediaFolder?
    @State private var folderSheetMode: FolderSheetMode?
    @State private var errorMessage: String?

    private var mediaRecords: [TranscriptionRecord] {
        transcriptions.filter(\.isMediaTranscription)
    }

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    private var selectedFolder: MediaFolder? {
        guard let selectedFolderID = featureState.selectedFolderID else { return nil }
        return folders.first { $0.id == selectedFolderID }
    }

    private var trimmedSearchText: String {
        featureState.librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleFolders: [MediaFolder] {
        let visibleIDs = Set(libraryBrowseState.visibleFolderIds)
        return folders.filter { visibleIDs.contains($0.id.uuidString) }
    }

    private var visibleMediaRecords: [TranscriptionRecord] {
        let visibleIDs = Set(libraryBrowseState.visibleRecordIds)
        return mediaRecords.filter { visibleIDs.contains($0.id.uuidString) }
    }

    private var libraryBrowseState: MediaLibraryBrowseState {
        return MediaLibraryPresenter.shared.browse(
            folders: folders.map { folder in
                MediaFolderSnapshot(
                    id: folder.id.uuidString,
                    name: folder.name,
                    itemCount: Int32(mediaRecords.filter { $0.folder?.id == folder.id }.count)
                )
            },
            records: mediaRecords.map { record in
                MediaRecordSnapshot(
                    id: record.id.uuidString,
                    folderId: record.folder?.id.uuidString,
                    timestampEpochMillis: Int64(record.timestamp.timeIntervalSince1970 * 1000),
                    searchText: [record.text, record.originalText, record.sourceDisplayName, record.originalSourceURL]
                        .compactMap { $0 }
                        .joined(separator: "\n"),
                    sortName: record.mediaLibrarySortName
                )
            },
            selectedFolderId: featureState.selectedFolderID?.uuidString,
            searchText: featureState.librarySearchText,
            sortMode: featureState.librarySortMode.coreValue
        )
    }

    private var transcribeLibraryViewState: TranscribeLibraryViewState {
        return TranscribeLibraryPresenter.shared.present(
            selectedFolderId: selectedFolder?.id.uuidString,
            selectedFolderName: selectedFolder?.name,
            draftLink: featureState.draftLink,
            librarySearchText: featureState.librarySearchText,
            browseState: libraryBrowseState
        )
    }

    private var totalLibraryCountText: String {
        if let selectedFolder {
            return localized("%d items in %@", locale: locale)
                .replacingOccurrences(of: "%d", with: "\(libraryBrowseState.filteredRecordCount)")
                .replacingOccurrences(of: "%@", with: selectedFolder.name)
        }

        let folderCountLabel = libraryBrowseState.filteredFolderCount == 1
            ? localized("1 folder", locale: locale)
            : localized("%d folders", locale: locale).replacingOccurrences(of: "%d", with: "\(libraryBrowseState.filteredFolderCount)")
        let transcriptCountLabel = libraryBrowseState.filteredRecordCount == 1
            ? localized("1 transcription", locale: locale)
            : localized("%d transcriptions", locale: locale).replacingOccurrences(of: "%d", with: "\(libraryBrowseState.filteredRecordCount)")
        return "\(folderCountLabel) • \(transcriptCountLabel)"
    }

    private var libraryGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.md)]
    }

    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }

    var body: some View {
        Group {
            switch featureState.route {
            case .library:
                libraryView
            case .processing(let jobID):
                processingView(jobID: jobID)
            case .detail(let recordID):
                detailView(recordID: recordID)
            }
        }
        .background(AppColors.contentBackground)
        .task {
            await modelManager.refreshDownloadedFeatureModels()
            prefillClipboardLinkIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prefillClipboardLinkIfNeeded()
        }
        .confirmationDialog(
            localized("Delete transcription?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionRecord != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionRecord = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                confirmDeletePendingRecord()
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                pendingDeletionRecord = nil
            }
        } message: {
            Text(localized("This will permanently remove the transcript and its managed media file.", locale: locale))
        }
        .confirmationDialog(
            localized("Delete folder?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionFolder != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionFolder = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Delete", locale: locale), role: .destructive) {
                confirmDeletePendingFolder()
            }
            Button(localized("Cancel", locale: locale), role: .cancel) {
                pendingDeletionFolder = nil
            }
        } message: {
            Text(localized("Transcriptions in this folder will be kept and moved back to the library.", locale: locale))
        }
        .alert(
            localized("Unable to update media library", locale: locale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            ),
            actions: {
                Button(localized("OK", locale: locale), role: .cancel) {
                    errorMessage = nil
                }
            },
            message: {
                Text(errorMessage ?? "")
            }
        )
        .sheet(item: $folderSheetMode) { mode in
            FolderEditorSheet(mode: mode) { name in
                try saveFolder(mode: mode, name: name)
            }
        }
        .onChange(of: folders.map(\.id)) { _, newFolderIDs in
            if let selectedFolderID = featureState.selectedFolderID,
               !newFolderIDs.contains(selectedFolderID) {
                featureState.clearSelectedFolder()
            }
        }
    }

    private var libraryView: some View {
        MainContentPageLayout(scrollContent: true, contentTopPadding: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                header
                diarizationGate
                if let setupIssue = featureState.setupIssue {
                    MessageCardView(
                        title: "Setup required",
                        message: setupIssue,
                        icon: "exclamationmark.triangle.fill",
                        tint: AppColors.warning
                    )
                }
                if let libraryMessage = featureState.libraryMessage {
                    MessageCardView(
                        title: "Transcription update",
                        message: libraryMessage,
                        icon: "info.circle.fill",
                        tint: AppColors.accent
                    )
                }
                if let job = featureState.currentJob,
                   job.stage != .completed,
                   job.stage != .failed {
                    backgroundJobCard(job)
                }
                dropZone
            }
        } content: {
            librarySection
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(localized("Transcribe Media", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Drop a file or paste a link to create a diarized, timestamped transcript.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppTheme.Spacing.lg)

            if let onOpenModels {
                Button(localized("Manage models", locale: locale)) {
                    onOpenModels()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var diarizationGate: some View {
        let isDownloaded = modelManager.isFeatureModelDownloaded(.diarization)
        if !isDownloaded || modelManager.currentDownloadingFeature == .diarization {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.accent)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(localized("Speaker diarization is required", locale: locale))
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)

                        Text(localized("Download the diarization model before starting media transcription.", locale: locale))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    if modelManager.currentDownloadingFeature == .diarization {
                        ProgressView(value: modelManager.featureDownloadProgress)
                            .frame(width: 120)
                    } else {
                        Button(localized("Download model", locale: locale)) {
                            onDownloadDiarizationModel()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if modelManager.currentDownloadingFeature == .diarization {
                    Text(localized("%complete", locale: locale).replacingOccurrences(of: "%complete", with: "\(Int(modelManager.featureDownloadProgress * 100))% complete"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.xl)
            .cardStyle(elevated: true)
        }
    }

    private var dropZone: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "film.stack")
                    .font(.system(size: 34))
                    .foregroundStyle(isTargeted ? AppColors.accent : AppColors.textTertiary)

                Text(localized("Drop audio or video here", locale: locale))
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Supports local media files and web links resolved with yt-dlp.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                Button(localized("Choose file", locale: locale)) {
                    importFilesViaOpenPanel()
                }
                .buttonStyle(.borderedProminent)

                Text(localized("or", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "link")
                        .foregroundStyle(AppColors.textTertiary)

                    TextField(localized("Paste a video or audio link", locale: locale), text: $featureState.draftLink)
                        .textFieldStyle(.plain)
                        .font(AppTypography.body)
                        .onChange(of: featureState.draftLink) { _, _ in
                            featureState.hasUserEditedDraftLink = true
                        }

                    Button(localized("Transcribe", locale: locale)) {
                        submitCurrentLink()
                    }
                    .buttonStyle(.borderless)
                    .disabled(!transcribeLibraryViewState.canSubmitDraftLink)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppColors.elevatedSurface)
                )
                .hairlineStroke(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous),
                    style: AppColors.border
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.Spacing.xxxl)
        .background(isTargeted ? AppColors.accentBackground : AppColors.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .strokeBorder(isTargeted ? AppColors.accent : AppColors.border, style: StrokeStyle(lineWidth: hairlineWidth, dash: [8, 6]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            handleImportedFiles(urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if transcribeLibraryViewState.shouldShowBackButton {
                            Button {
                                featureState.clearSelectedFolder()
                            } label: {
                                Label(localized("Back", locale: locale), systemImage: "chevron.left")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(localized("Media Library", locale: locale))
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    Text(totalLibraryCountText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }

            libraryControls

            if transcribeLibraryViewState.shouldShowLibraryEmptyState {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: transcribeLibraryViewState.emptyStateIconName)
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(emptyLibraryTitle)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(emptyLibraryMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(AppTheme.Spacing.xxxl)
                .cardStyle()
            } else {
                LazyVGrid(columns: libraryGridColumns, spacing: AppTheme.Spacing.md) {
                    ForEach(visibleFolders) { folder in
                        MediaFolderTile(
                            folder: folder,
                            itemCount: mediaRecords.filter { $0.folder?.id == folder.id }.count,
                            onOpen: { featureState.selectFolder(folder.id) },
                            onDropRecord: { recordID in
                                assignRecord(recordID: recordID, to: folder)
                            },
                            onRename: { folderSheetMode = .rename(folder) },
                            onDelete: { pendingDeletionFolder = folder }
                        )
                    }

                    ForEach(visibleMediaRecords) { record in
                        MediaLibraryTranscriptionTile(
                            record: record,
                            isSelected: featureState.selectedRecordID == record.id,
                            onOpen: { featureState.selectRecord(record.id) },
                            onCopy: { copyTranscript(record.text) },
                            onMoveToFolder: { folder in assignRecord(record, to: folder) },
                            onRemoveFromFolder: {
                                if record.folder != nil {
                                    removeRecordFromFolder(record)
                                }
                            },
                            onDelete: { promptDelete(record) },
                            availableFolders: folders
                        )
                    }
                }
            }
        }
    }

    private var libraryControls: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            librarySearchField

            Menu {
                ForEach(MediaLibrarySortMode.allCases, id: \.self) { sortMode in
                    Button {
                        featureState.librarySortMode = sortMode
                    } label: {
                        if featureState.librarySortMode == sortMode {
                            Label(sortMode.title(locale: locale), systemImage: "checkmark")
                        } else {
                            Text(sortMode.title(locale: locale))
                        }
                    }
                }
            } label: {
                Label(featureState.librarySortMode.title(locale: locale), systemImage: "arrow.up.arrow.down")
                    .font(AppTypography.subheadline)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            .menuStyle(.borderlessButton)

            Button {
                folderSheetMode = .create
            } label: {
                Label(localized("New Folder", locale: locale), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var librarySearchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)

            TextField(localized("Search media transcripts...", locale: locale), text: $featureState.librarySearchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)

            if !featureState.librarySearchText.isEmpty {
                Button {
                    featureState.librarySearchText = ""
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
        .frame(maxWidth: 420)
    }

    private func backgroundJobCard(_ job: MediaTranscriptionJobState) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(localized("Transcription in progress", locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(job.request.displayName)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Button(localized("Open progress", locale: locale)) {
                    featureState.route = .processing(job.id)
                }
                .buttonStyle(.bordered)
            }

            MediaProcessingProgressView(job: job)
        }
        .padding(AppTheme.Spacing.xl)
        .cardStyle(elevated: true)
    }

    @ViewBuilder
    private func processingView(jobID: UUID) -> some View {
        if let job = featureState.currentJob, job.id == jobID {
            let displayedProgress = min(max(job.progress ?? 0, 0), 1)

            VStack(spacing: AppTheme.Spacing.xxl) {
                HStack {
                    Button {
                        featureState.exitProcessingView()
                    } label: {
                        Label(localized("Back to library", locale: locale), systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Spacer()
                }

                VStack(spacing: AppTheme.Spacing.xl) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.border, lineWidth: 10)
                            .frame(width: 140, height: 140)

                        if displayedProgress > 0 {
                            Circle()
                                .trim(from: 0, to: displayedProgress)
                                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 140, height: 140)
                        }
                    }

                    VStack(spacing: AppTheme.Spacing.sm) {
                        Text(job.stage.title(locale: locale))
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("\(Int(displayedProgress * 100))%")
                            .font(AppTypography.statMedium)
                            .foregroundStyle(AppColors.accent)

                        Text(job.request.displayName)
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.textPrimary)

                        Text(job.errorMessage ?? job.detail)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                }

                MediaProcessingProgressView(job: job)
                    .frame(maxWidth: 540)

                if let errorMessage = job.errorMessage {
                    MessageCardView(
                        title: localized("Unable to finish transcription", locale: locale),
                        message: errorMessage,
                        icon: "xmark.octagon.fill",
                        tint: AppColors.error
                    )
                    .frame(maxWidth: 540)
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.xxxl)
        } else {
            libraryView
        }
    }

    @ViewBuilder
    private func detailView(recordID: UUID) -> some View {
        if let record = mediaRecords.first(where: { $0.id == recordID }) {
            MediaTranscriptionDetailView(
                record: record,
                folders: folders,
                onBack: {
                    featureState.showLibrary()
                },
                onAssignFolder: { folder in
                    assignRecord(record, to: folder)
                },
                onRemoveFromFolder: {
                    if record.folder != nil {
                        removeRecordFromFolder(record)
                    }
                },
                onDelete: {
                    promptDelete(record)
                }
            )
        } else {
            VStack(spacing: AppTheme.Spacing.lg) {
                Text(localized("This transcription could not be found.", locale: locale))
                    .font(AppTypography.headline)
                Button(localized("Back to library", locale: locale)) {
                    featureState.showLibrary()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func importFilesViaOpenPanel() {
        let panel = NSOpenPanel()
        let currentLocale = SettingsStore().selectedAppLanguage.locale
        panel.title = localized("Import media", locale: currentLocale)
        panel.message = localized("Choose an audio or video file to transcribe", locale: currentLocale)
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie, .video]

        if panel.runModal() == .OK {
            handleImportedFiles(panel.urls)
        }
    }

    private func handleImportedFiles(_ urls: [URL]) {
        let supported = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                return false
            }
            return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
        }
        guard !supported.isEmpty else { return }
        onImportFiles(supported)
    }

    private func submitCurrentLink() {
        let trimmed = featureState.draftLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmitLink(trimmed)
    }

    private func prefillClipboardLinkIfNeeded() {
        guard let string = NSPasteboard.general.string(forType: .string),
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return
        }
        featureState.updateDraftLinkFromClipboard(url.absoluteString)
    }

    private func copyTranscript(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func promptDelete(_ record: TranscriptionRecord) {
        pendingDeletionRecord = record
    }

    private func confirmDeletePendingRecord() {
        guard let record = pendingDeletionRecord else { return }
        pendingDeletionRecord = nil

        do {
            let deletedRecordID = record.id
            try historyStore.delete(record)
            featureState.handleDeletedRecord(deletedRecordID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var emptyLibraryTitle: String {
        let key = transcribeLibraryViewState.emptyStateTitleKey
        if key.contains("%@") {
            return localized(key, locale: locale).replacingOccurrences(of: "%@", with: transcribeLibraryViewState.selectedFolderName ?? "")
        }
        return localized(key, locale: locale)
    }

    private var emptyLibraryMessage: String {
        localized(transcribeLibraryViewState.emptyStateMessageKey, locale: locale)
    }

    private func saveFolder(mode: FolderSheetMode, name: String) throws {
        switch mode {
        case .create:
            let folder = try historyStore.createFolder(named: name)
            featureState.selectFolder(folder.id)
        case .rename(let folder):
            try historyStore.renameFolder(folder, to: name)
        }
    }

    private func confirmDeletePendingFolder() {
        guard let folder = pendingDeletionFolder else { return }
        pendingDeletionFolder = nil

        do {
            let deletedFolderID = folder.id
            try historyStore.deleteFolder(folder)
            featureState.handleDeletedFolder(deletedFolderID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignRecord(_ record: TranscriptionRecord, to folder: MediaFolder) {
        do {
            try historyStore.assign(record: record, to: folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func assignRecord(recordID: UUID, to folder: MediaFolder) {
        guard let record = mediaRecords.first(where: { $0.id == recordID }) else { return }
        assignRecord(record, to: folder)
    }

    private func removeRecordFromFolder(_ record: TranscriptionRecord) {
        do {
            try historyStore.removeFromFolder(record: record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum FolderSheetMode: Identifiable {
    case create
    case rename(MediaFolder)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .rename(let folder):
            return "rename-\(folder.id.uuidString)"
        }
    }

    func title(locale: Locale) -> String {
        switch self {
        case .create:
            return localized("New Folder", locale: locale)
        case .rename:
            return localized("Rename Folder", locale: locale)
        }
    }

    var initialName: String {
        switch self {
        case .create:
            return ""
        case .rename(let folder):
            return folder.name
        }
    }

    func saveButtonTitle(locale: Locale) -> String {
        switch self {
        case .create:
            return localized("Create", locale: locale)
        case .rename:
            return localized("Save", locale: locale)
        }
    }
}

private struct FolderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let mode: FolderSheetMode
    let onSave: (String) throws -> Void

    @State private var name: String
    @State private var errorMessage: String?

    init(mode: FolderSheetMode, onSave: @escaping (String) throws -> Void) {
        self.mode = mode
        self.onSave = onSave
        _name = State(initialValue: mode.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(mode.title(locale: locale))
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            TextField(localized("Folder name", locale: locale), text: $name)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.error)
            }

            HStack {
                Spacer()

                Button(localized("Cancel", locale: locale)) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(mode.saveButtonTitle(locale: locale)) {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: 420)
    }

    private func save() {
        do {
            try onSave(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MediaFolderTile: View {
    @Environment(\.locale) private var locale

    let folder: MediaFolder
    let itemCount: Int
    let onOpen: () -> Void
    let onDropRecord: (UUID) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        MediaLibraryGridItemCard(
            title: folder.name,
            badgeText: "\(itemCount)",
            isDropTarget: isDropTarget,
            thumbnail: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            },
            onOpen: onOpen
        )
        .contextMenu {
            Button(action: onRename) {
                Label(localized("Rename Folder", locale: locale), systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label(localized("Delete Folder", locale: locale), systemImage: "trash")
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let identifier = items.first,
                  let recordID = UUID(uuidString: identifier) else {
                return false
            }
            onDropRecord(recordID)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}

private struct MediaLibraryTranscriptionTile: View {
    @Environment(\.locale) private var locale

    let record: TranscriptionRecord
    let isSelected: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onMoveToFolder: (MediaFolder) -> Void
    let onRemoveFromFolder: () -> Void
    let onDelete: () -> Void
    let availableFolders: [MediaFolder]

    var body: some View {
        MediaLibraryGridItemCard(
            title: record.mediaLibrarySortName,
            isSelected: isSelected,
            thumbnail: {
                TranscriptionThumbnailView(record: record)
            },
            onOpen: onOpen
        )
        .draggable(record.id.uuidString)
        .contextMenu {
            Button(action: onCopy) {
                Label(localized("Copy Transcript", locale: locale), systemImage: "doc.on.doc")
            }

            Menu(localized("Move to Folder", locale: locale)) {
                if availableFolders.isEmpty {
                    Button(localized("No folders yet", locale: locale)) {}
                        .disabled(true)
                } else {
                    ForEach(availableFolders) { folder in
                        Button(folder.name) {
                            onMoveToFolder(folder)
                        }
                    }
                }
            }

            if record.folder != nil {
                Button(action: onRemoveFromFolder) {
                    Label(localized("Remove from Folder", locale: locale), systemImage: "folder.badge.minus")
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label(localized("Delete", locale: locale), systemImage: "trash")
            }
        }
    }
}

private struct MediaLibraryGridItemCard<Thumbnail: View>: View {
    @Environment(\.displayScale) private var displayScale

    let title: String
    var badgeText: String? = nil
    var isSelected: Bool = false
    var isDropTarget: Bool = false
    @ViewBuilder let thumbnail: () -> Thumbnail
    let onOpen: () -> Void

    @State private var isHovered = false

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                thumbnail()
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .padding(.top, AppTheme.Spacing.xs)
                    .padding(.bottom, AppTheme.Spacing.sm)

                titleView
            }
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .top)
            .padding(AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(borderColor, lineWidth: hairlineWidth)
            )
            .shadow(
                color: isHovered ? Color.black.opacity(0.06) : .clear,
                radius: isHovered ? 10 : 0,
                y: isHovered ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(AppTheme.Animation.fast, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var titleView: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let badgeText {
                Text(badgeText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.sidebarItemActive)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Spacing.xs)
    }

    private var backgroundColor: Color {
        if isDropTarget {
            return AppColors.accentBackground
        }

        if isSelected {
            return isHovered ? AppColors.sidebarItemActive.opacity(0.9) : AppColors.sidebarItemActive
        }

        return isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground
    }

    private var borderColor: Color {
        if isDropTarget {
            return AppColors.accent
        }

        if isSelected {
            return AppColors.accent.opacity(isHovered ? 0.5 : 0.35)
        }

        return isHovered ? AppColors.border.opacity(0.9) : AppColors.border
    }
}

private struct TranscriptionThumbnailView: View {
    let record: TranscriptionRecord

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppColors.accentBackground)

            if let thumbnailURL = record.thumbnailURL,
               let image = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: record.resolvedSourceKind == .webLink ? "globe" : "waveform")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }
}

private struct MessageCardView: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.lg)
        .cardStyle(elevated: true)
    }
}

private struct MediaProcessingProgressView: View {
    let job: MediaTranscriptionJobState

    private let orderedStages: [MediaTranscriptionStage] = [.preflight, .importing, .downloading, .preparingAudio, .transcribing, .saving]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ForEach(orderedStages, id: \.self) { stage in
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: icon(for: stage))
                        .foregroundStyle(color(for: stage))
                        .frame(width: 20)

                    Text(stage.title)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    if stage == job.stage, let progress = job.progress {
                        Text("\(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.xl)
        .cardStyle()
    }

    private func icon(for stage: MediaTranscriptionStage) -> String {
        if stage == job.stage {
            return job.stage == .failed ? "xmark.circle.fill" : "clock.arrow.circlepath"
        }
        if orderedStages.firstIndex(of: stage).map({ $0 < orderedStages.firstIndex(of: job.stage) ?? 0 }) == true {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private func color(for stage: MediaTranscriptionStage) -> Color {
        if stage == job.stage {
            return job.stage == .failed ? AppColors.error : AppColors.accent
        }
        if orderedStages.firstIndex(of: stage).map({ $0 < orderedStages.firstIndex(of: job.stage) ?? 0 }) == true {
            return AppColors.success
        }
        return AppColors.textTertiary
    }
}

@MainActor
@Observable
private final class MediaPlaybackController {
    let player = AVPlayer()

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var hasVideoTrack = false

    private var timeObserver: Any?

    func load(url: URL) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observeTime()

        Task {
            let asset = AVURLAsset(url: url)
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let duration = try? await asset.load(.duration)
            await MainActor.run {
                self.hasVideoTrack = !(tracks?.isEmpty ?? true)
                self.duration = duration?.seconds ?? 0
            }
        }
    }

    func togglePlayback() {
        if player.rate > 0 {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: TimeInterval) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.isPlaying = self.player.rate > 0
            }
        }
    }
}

private struct MediaTranscriptionDetailView: View {
    let record: TranscriptionRecord
    let folders: [MediaFolder]
    let onBack: () -> Void
    let onAssignFolder: (MediaFolder) -> Void
    let onRemoveFromFolder: () -> Void
    let onDelete: () -> Void

    @State private var playbackController = MediaPlaybackController()
    @State private var followPlayback = true
    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false

    private var segments: [DiarizedTranscriptSegment] {
        record.diarizedSegments
    }

    private var activeSegmentID: String? {
        guard let index = segments.firstIndex(where: {
            playbackController.currentTime >= $0.startTime && playbackController.currentTime < $0.endTime
        }) else {
            return nil
        }
        return segmentIdentifier(segments[index], index: index)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            transcriptColumn
                .padding(.trailing, AppTheme.Spacing.lg)
                .frame(minWidth: 500, maxWidth: .infinity, alignment: .topLeading)

            sidebar
                .padding(.leading, AppTheme.Spacing.lg)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400, alignment: .topLeading)
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.bottom, AppTheme.Spacing.xxl)
        .padding(.top, AppTheme.Spacing.lg)
        .task(id: record.id) {
            if let mediaURL = record.managedMediaURL {
                playbackController.load(url: mediaURL)
            }
        }
        .onChange(of: playbackController.currentTime) { _, newValue in
            if !isDraggingSlider {
                sliderValue = newValue
            }
        }
    }

    private var transcriptColumn: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Toggle("Follow playback", isOn: $followPlayback)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(record.sourceDisplayName ?? "Media Transcription")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Speaker diarization and timestamps are attached to playback.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if segments.isEmpty {
                ScrollView {
                    Text(record.text)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.xxl)
                }
                .cardStyle()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                                Button {
                                    playbackController.seek(to: segment.startTime)
                                } label: {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                        HStack(spacing: AppTheme.Spacing.sm) {
                                            Text(segment.speakerLabel)
                                                .font(AppTypography.caption)
                                                .foregroundStyle(isActive(segment, index: index) ? AppColors.accent : AppColors.textTertiary)
                                            Text(timestampLabel(for: segment.startTime))
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColors.textTertiary)
                                        }

                                        Text(segment.text)
                                            .font(.system(size: 26, weight: isActive(segment, index: index) ? .semibold : .regular, design: .rounded))
                                            .foregroundStyle(isActive(segment, index: index) ? Color.white : AppColors.textSecondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, AppTheme.Spacing.sm)
                                }
                                .buttonStyle(.plain)
                                .id(segmentIdentifier(segment, index: index))
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.xl)
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                            .fill(Color.black.opacity(0.88))
                    )
                    .hairlineStroke(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous),
                        style: AppColors.border
                    )
                    .onChange(of: activeSegmentID) { _, identifier in
                        guard followPlayback, let identifier else { return }
                        withAnimation(AppTheme.Animation.normal) {
                            proxy.scrollTo(identifier, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if let mediaURL = record.managedMediaURL {
                if playbackController.hasVideoTrack {
                    VideoPlayer(player: playbackController.player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                } else {
                    VStack(spacing: AppTheme.Spacing.md) {
                        TranscriptionThumbnailView(record: record)
                            .frame(maxWidth: .infinity)

                        Text(record.sourceDisplayName ?? mediaURL.lastPathComponent)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.xl)
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Button(playbackController.isPlaying ? "Pause" : "Play") {
                        playbackController.togglePlayback()
                    }
                    .buttonStyle(.borderedProminent)

                    Slider(
                        value: Binding(
                            get: { sliderValue },
                            set: { sliderValue = $0 }
                        ),
                        in: 0...max(playbackController.duration, 1),
                        onEditingChanged: { editing in
                            isDraggingSlider = editing
                            if !editing {
                                playbackController.seek(to: sliderValue)
                            }
                        }
                    )

                    HStack {
                        Text(timestampLabel(for: playbackController.currentTime))
                        Spacer()
                        Text(timestampLabel(for: playbackController.duration))
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppTheme.Spacing.xl)
                .cardStyle()
            } else {
                MessageCardView(
                    title: "Media unavailable",
                    message: "The managed media file could not be found on disk.",
                    icon: "exclamationmark.triangle.fill",
                    tint: AppColors.warning
                )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                metadataRow("Source", value: record.resolvedSourceKind.isMediaBacked ? record.resolvedSourceKind.rawValue : "voice")
                metadataRow("Saved", value: record.timestamp.formatted(date: .abbreviated, time: .shortened))
                metadataRow("Duration", value: formatDuration(record.duration))
                metadataRow("Folder", value: record.folder?.name ?? "Unfiled")

                if let originalSourceURL = record.originalSourceURL,
                   let url = URL(string: originalSourceURL),
                   record.resolvedSourceKind == .webLink {
                    Link(destination: url) {
                        Label("Open original link", systemImage: "arrow.up.right.square")
                    }
                    .font(AppTypography.body)
                }

                Divider()

                Menu {
                    if folders.isEmpty {
                        Button("No folders yet") {}
                            .disabled(true)
                    } else {
                        ForEach(folders) { folder in
                            Button(folder.name) {
                                onAssignFolder(folder)
                            }
                        }
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)

                if record.folder != nil {
                    Button(action: onRemoveFromFolder) {
                        Label("Remove from Folder", systemImage: "folder.badge.minus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete transcription", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
            .padding(AppTheme.Spacing.xl)
            .cardStyle()

            Spacer()
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func isActive(_ segment: DiarizedTranscriptSegment, index: Int) -> Bool {
        activeSegmentID == segmentIdentifier(segment, index: index)
    }

    private func segmentIdentifier(_ segment: DiarizedTranscriptSegment, index: Int) -> String {
        "\(segment.speakerId)-\(index)-\(segment.startTime)"
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    timestampLabel(for: duration)
}

private func timestampLabel(for duration: TimeInterval) -> String {
    guard duration.isFinite, duration > 0 else { return "0:00" }
    let totalSeconds = Int(duration.rounded(.down))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return "\(minutes):" + String(format: "%02d", seconds)
}
