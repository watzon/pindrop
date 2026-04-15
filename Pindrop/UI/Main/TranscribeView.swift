//
//  TranscribeView.swift
//  Pindrop
//
//  Created on 2026-03-07.
//

import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transcribe Page

struct TranscribeView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
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
    @State private var errorMessage: String?

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }

    var body: some View {
        Group {
            switch featureState.route {
            // `.library` now renders the importer screen — the library UI has
            // moved to HistoryView. We keep the case name to avoid churning
            // MediaTranscriptionFeatureState and its call sites.
            case .library:
                importerView
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
        .alert(
            localized("Unable to update transcription", locale: locale),
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
    }

    private var importerView: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .padding(.bottom, AppTheme.Spacing.lg)
                .background(AppColors.contentBackground)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
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

                    linkInputCard
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .background(AppColors.contentBackground)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(localized("Transcribe Media", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(localized("Drop a file or paste a link to create a diarized, timestamped transcript.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppTheme.Spacing.lg)

            if let onOpenModels {
                Button {
                    onOpenModels()
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text(localized("Manage models", locale: locale))
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.surfaceBackground)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Diarization gate

    @ViewBuilder
    private var diarizationGate: some View {
        let isDownloaded = modelManager.isFeatureModelDownloaded(.diarization)
        if !isDownloaded || modelManager.currentDownloadingFeature == .diarization {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .fill(AppColors.accent.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
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
                        .controlSize(.small)
                    }
                }

                if modelManager.currentDownloadingFeature == .diarization {
                    Text(localized("%complete", locale: locale).replacingOccurrences(of: "%complete", with: "\(Int(modelManager.featureDownloadProgress * 100))% complete"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.xl)
            .highlightedCardStyle()
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        ZStack {
            // Ambient glow when targeted
            if isTargeted {
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [AppColors.accent.opacity(0.22), AppColors.accent.opacity(0.0)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 360
                        )
                    )
            }

            VStack(spacing: AppTheme.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isTargeted
                                    ? [AppColors.accent.opacity(0.25), AppColors.accent.opacity(0.1)]
                                    : [AppColors.accent.opacity(0.12), AppColors.accent.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)

                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "square.and.arrow.down.on.square")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(AppColors.accent)
                        .symbolEffect(.bounce, value: isTargeted)
                }

                VStack(spacing: AppTheme.Spacing.xs) {
                    Text(isTargeted
                         ? localized("Release to transcribe", locale: locale)
                         : localized("Drop audio or video here", locale: locale))
                        .font(AppTypography.title)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(localized("MP3, WAV, M4A, MP4, MOV, and more — we'll handle the rest.", locale: locale))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    importFilesViaOpenPanel()
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text(localized("Choose file", locale: locale))
                            .font(AppTypography.subheadline)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, AppTheme.Spacing.xxxl)
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(isTargeted ? AppColors.accent.opacity(0.06) : AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(
                    isTargeted ? AppColors.accent : AppColors.border,
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 2 : hairlineWidth,
                        dash: [10, 7]
                    )
                )
        )
        .animation(AppTheme.Animation.fast, value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            handleImportedFiles(urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    // MARK: - Link input

    private var linkInputCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(AppColors.processing.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.processing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Paste a link", locale: locale))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(localized("YouTube, podcast episodes, or any yt-dlp supported URL.", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer(minLength: AppTheme.Spacing.md)

            HStack(spacing: AppTheme.Spacing.sm) {
                TextField(localized("https://…", locale: locale), text: $featureState.draftLink)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .frame(minWidth: 220, maxWidth: 320)
                    .onChange(of: featureState.draftLink) { _, _ in
                        featureState.hasUserEditedDraftLink = true
                    }
                    .onSubmit(submitCurrentLink)

                Button {
                    submitCurrentLink()
                } label: {
                    Text(localized("Transcribe", locale: locale))
                        .font(AppTypography.subheadline)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(featureState.draftLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppColors.elevatedSurface)
            )
            .hairlineStroke(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous),
                style: AppColors.border
            )
        }
        .padding(AppTheme.Spacing.lg)
        .cardStyle()
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
                        Label(localized("Back", locale: locale), systemImage: "chevron.left")
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
            importerView
        }
    }

    @ViewBuilder
    private func detailView(recordID: UUID) -> some View {
        if let record = try? historyStore.fetchRecord(with: recordID), record.isMediaTranscription {
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
                onRenameSpeakers: { labelsBySpeakerID in
                    renameSpeakerLabels(for: record, labelsBySpeakerID: labelsBySpeakerID)
                },
                onDelete: {
                    promptDelete(record)
                }
            )
        } else {
            VStack(spacing: AppTheme.Spacing.lg) {
                Text(localized("This transcription could not be found.", locale: locale))
                    .font(AppTypography.headline)
                Button(localized("Back", locale: locale)) {
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

    private func assignRecord(_ record: TranscriptionRecord, to folder: MediaFolder) {
        do {
            try historyStore.assign(record: record, to: folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRecordFromFolder(_ record: TranscriptionRecord) {
        do {
            try historyStore.removeFromFolder(record: record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameSpeakerLabels(for record: TranscriptionRecord, labelsBySpeakerID: [String: String]) {
        do {
            try historyStore.updateSpeakerLabels(record: record, labelsBySpeakerID: labelsBySpeakerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MessageCardView: View {
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
