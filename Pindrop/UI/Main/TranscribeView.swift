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

    let onImportFiles: ([URL], TranscriptionJobOptions) -> Void
    let onSubmitLink: (String, TranscriptionJobOptions) -> Void
    let onClearQueue: () -> Void
    let onDownloadDiarizationModel: () -> Void
    let onOpenModels: (() -> Void)?

    @State private var isTargeted = false
    @State private var pendingDeletionRecord: TranscriptionRecord?
    @State private var errorMessage: String?

    // Quick Options (front-end only; wired up in a follow-up pass)
    @State private var selectedJobModel: String = ""
    @State private var selectedJobLanguage: String = AppLanguage.automatic.rawValue
    @State private var outputFormat: TranscribeOutputFormat = .plainText

    // Batch import sheet
    @State private var showBatchImport = false
    @State private var batchInputText = ""

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }

    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }

    private var currentJobOptions: TranscriptionJobOptions {
        TranscriptionJobOptions(
            modelName: selectedJobModel.isEmpty ? settingsStore.selectedModel : selectedJobModel,
            language: AppLanguage(rawValue: selectedJobLanguage) ?? .automatic,
            outputFormat: outputFormat
        )
    }

    private var downloadedModelOptions: [SelectFieldOption] {
        modelManager.availableModels
            .filter { modelManager.downloadedModelNames.contains($0.name) }
            .map { SelectFieldOption(id: $0.name, displayName: $0.displayName) }
    }

    private var languageOptions: [SelectFieldOption] {
        AppLanguage.allCases
            .filter { $0.isSelectable }
            .map { lang in
                let name = lang == .automatic
                    ? localized("Auto-detect", locale: locale)
                    : lang.displayName(locale: locale)
                return SelectFieldOption(id: lang.rawValue, displayName: name)
            }
    }

    var body: some View {
        Group {
            switch featureState.route {
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
            if selectedJobModel.isEmpty {
                selectedJobModel = settingsStore.selectedModel
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prefillClipboardLinkIfNeeded()
        }
        .sheet(isPresented: $showBatchImport) {
            BatchImportSheet(
                inputText: $batchInputText,
                onImport: { [self] urls, filePaths in
                    let opts = currentJobOptions
                    for url in urls {
                        onSubmitLink(url, opts)
                    }
                    let fileURLs = filePaths.compactMap { path -> URL? in
                        let expanded = (path as NSString).expandingTildeInPath
                        let url = URL(fileURLWithPath: expanded)
                        return FileManager.default.fileExists(atPath: url.path) ? url : nil
                    }
                    if !fileURLs.isEmpty {
                        onImportFiles(fileURLs, opts)
                    }
                    showBatchImport = false
                },
                onCancel: { showBatchImport = false }
            )
        }
        .confirmationDialog(
            localized("Delete transcription?", locale: locale),
            isPresented: Binding(
                get: { pendingDeletionRecord != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletionRecord = nil }
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
                    if !isPresented { errorMessage = nil }
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

    // MARK: - Main importer layout

    private var importerView: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .padding(.bottom, AppTheme.Spacing.lg)
                .background(AppColors.contentBackground)

            HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                ScrollView(showsIndicators: false) {
                    leftColumnContent
                        .padding(.top, AppTheme.Spacing.sm)
                        .padding(.bottom, AppTheme.Spacing.xxl)
                }

                quickOptionsPanel
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
        }
        .background(AppColors.contentBackground)
    }

    // MARK: - Left column

    private var leftColumnContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            diarizationGate

            if let setupIssue = featureState.setupIssue {
                MessageCardView(
                    title: localized("Setup required", locale: locale),
                    message: setupIssue,
                    icon: "exclamationmark.triangle.fill",
                    tint: AppColors.warning
                )
            }

            dropZone

            Rectangle()
                .fill(AppColors.border)
                .frame(maxWidth: .infinity, maxHeight: hairlineWidth)

            queueSection
        }
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

    // MARK: - Queue section

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            let totalCount = featureState.completedJobs.count
                + (featureState.currentJob != nil ? 1 : 0)
                + featureState.pendingJobs.count

            HStack(spacing: AppTheme.Spacing.xs) {
                Text(localized("Queue", locale: locale))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Text("\(totalCount)")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, AppTheme.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.mutedSurface))

                Spacer()

                if totalCount > 0 {
                    Button(localized("Clear", locale: locale)) {
                        onClearQueue()
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }
            }

            if totalCount == 0 {
                Text(localized("No items in queue. Drop a file or use Import to get started.", locale: locale))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                // Completed jobs (oldest first, already done)
                ForEach(featureState.completedJobs) { completed in
                    queueItemRow(for: completed)
                }

                // Active job
                if let job = featureState.currentJob {
                    queueItemRow(for: job)

                    // Pending jobs
                    ForEach(featureState.pendingJobs) { pending in
                        pendingJobRow(for: pending)
                    }

                    if job.stage != .completed, job.stage != .failed {
                        HStack {
                            HStack(spacing: AppTheme.Spacing.xxs) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11))
                                let remaining = featureState.pendingJobs.count
                                Text(remaining > 0
                                     ? localized("\(remaining + 1) items remaining", locale: locale)
                                     : localized("Processing", locale: locale))
                                    .font(AppTypography.caption)
                            }
                            .foregroundStyle(AppColors.textTertiary)

                            Spacer()

                            Button(localized("View Progress", locale: locale)) {
                                featureState.route = .processing(job.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func queueItemRow(for job: MediaTranscriptionJobState) -> some View {
        let isFailed = job.stage == .failed
        let isComplete = job.stage == .completed
        let isActive = !isFailed && !isComplete

        return HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        isFailed ? AppColors.error.opacity(0.12)
                        : isComplete ? AppColors.success.opacity(0.12)
                        : AppColors.accent.opacity(0.12)
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: isFailed ? "xmark.circle.fill" : isComplete ? "checkmark.circle.fill" : "waveform")
                    .font(.system(size: 14, weight: isFailed || isComplete ? .regular : .medium))
                    .foregroundStyle(isFailed ? AppColors.error : isComplete ? AppColors.success : AppColors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.request.displayName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(job.stage.title(locale: locale))
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 0)

            if let progress = job.progress, isActive {
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.accent)
                    .monospacedDigit()
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    isFailed ? AppColors.error.opacity(0.4)
                    : isComplete ? AppColors.success.opacity(0.4)
                    : AppColors.accent.opacity(0.35),
                    lineWidth: 1.5
                )
        )
    }

    private func pendingJobRow(for job: MediaTranscriptionJobState) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.border.opacity(0.5))
                    .frame(width: 36, height: 36)
                Image(systemName: "clock")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.request.displayName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localized("Waiting…", locale: locale))
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Quick options panel

    private var quickOptionsPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(localized("Quick Options", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            optionGroup(label: localized("Model", locale: locale)) {
                if downloadedModelOptions.isEmpty {
                    Button { onOpenModels?() } label: {
                        HStack {
                            Text(localized("No models downloaded", locale: locale))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textTertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .aiSettingsInputChrome()
                } else {
                    SelectField(
                        options: downloadedModelOptions,
                        selection: $selectedJobModel,
                        placeholder: localized("Select model", locale: locale)
                    )
                }
            }

            optionGroup(label: localized("Language", locale: locale)) {
                SelectField(
                    options: languageOptions,
                    selection: $selectedJobLanguage,
                    placeholder: localized("Auto-detect", locale: locale)
                )
            }

            Rectangle()
                .fill(AppColors.border)
                .frame(maxWidth: .infinity, maxHeight: hairlineWidth)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(localized("Output Format", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                let diarizationAvailable = modelManager.isFeatureModelDownloaded(.diarization)
                ForEach(TranscribeOutputFormat.allCases, id: \.rawValue) { format in
                    outputFormatRow(format, diarizationAvailable: diarizationAvailable)
                }
            }

            Rectangle()
                .fill(AppColors.border)
                .frame(maxWidth: .infinity, maxHeight: hairlineWidth)

            Button {
                if !featureState.draftLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   batchInputText.isEmpty {
                    batchInputText = featureState.draftLink
                }
                showBatchImport = true
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(localized("Import Audio / Video", locale: locale))
                        .font(AppTypography.subheadline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: AppColors.border
        )
    }

    @ViewBuilder
    private func optionGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
    }

    private func outputFormatRow(_ format: TranscribeOutputFormat, diarizationAvailable: Bool) -> some View {
        let requiresDiarization = format != .plainText
        let isDisabled = requiresDiarization && !diarizationAvailable

        return Button {
            if !isDisabled { outputFormat = format }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                ZStack {
                    if outputFormat == format && !isDisabled {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppColors.accent)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isDisabled ? AppColors.border.opacity(0.4) : AppColors.border, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(format.displayName)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(isDisabled ? AppColors.textTertiary : AppColors.textPrimary)
                    if isDisabled {
                        Text(localized("Requires diarization model", locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Processing view

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

    // MARK: - Detail view

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

    // MARK: - Actions

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
        onImportFiles(supported, currentJobOptions)
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

// MARK: - Batch Import Sheet

private struct BatchImportSheet: View {
    @Binding var inputText: String
    let onImport: (_ urls: [String], _ filePaths: [String]) -> Void
    let onCancel: () -> Void

    @Environment(\.locale) private var locale

    private var parsedLines: [String] {
        inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var urlLines: [String] {
        parsedLines.filter { line in
            guard let url = URL(string: line),
                  let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https"].contains(scheme)
        }
    }

    private var filePathLines: [String] {
        parsedLines.filter { line in
            line.hasPrefix("/") || line.hasPrefix("~")
        }
    }

    private var canImport: Bool {
        !urlLines.isEmpty || !filePathLines.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(localized("Batch Import", locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(localized("Import multiple files, URLs, or paths at once", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                .fill(AppColors.mutedSurface)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.xl)

            Divider()

            // Body
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inputText)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 180)
                        .padding(8)
                        .background(AppColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                .strokeBorder(AppColors.inputBorder, lineWidth: 1)
                        )

                    if inputText.isEmpty {
                        Text("Paste URLs or file paths here, one per line…\ne.g. https://youtube.com/watch?v=abc123\n     /Users/me/recordings/meeting.mp3")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)

            Divider()

            // Footer
            HStack {
                if !parsedLines.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text("\(parsedLines.count)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                            .monospacedDigit()
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.accent.opacity(0.12)))

                        Text(parsedLines.count == 1
                             ? localized("item ready", locale: locale)
                             : localized("items ready", locale: locale))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: AppTheme.Spacing.sm) {
                    Button(localized("Cancel", locale: locale)) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(localized("Import All", locale: locale)) {
                        onImport(urlLines, filePathLines)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canImport)
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
        .background(AppColors.elevatedSurface)
        .frame(width: 560)
    }
}

// MARK: - Message card

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

// MARK: - Media processing progress

private struct MediaProcessingProgressView: View {
    let job: MediaTranscriptionJobState

    private let orderedStages: [MediaTranscriptionStage] = [.preflight, .preparingModel, .importing, .downloading, .preparingAudio, .transcribing, .saving]

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
