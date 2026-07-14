//
//  LibraryExpandedPlayerCard.swift
//  Pindrop
//
//  Created on 2026-07-09.
//
//  Expanded Library row player card (spec §6).
//

import AVFoundation
import SwiftUI

struct LibraryExpandedPlayerCard: View {
    let record: TranscriptionRecord
    let retention: DictationAudioRetention
    let onCopy: () -> Void
    let onExport: (TranscriptExportFormat) -> Void
    let onDelete: () -> Void
    var onSaveEdit: ((String) -> Void)? = nil

    @Environment(\.locale) private var locale

    @State private var playbackController = MediaPlaybackController()
    @State private var playbackRate: Float = 1.0
    @State private var peaks: [Float] = []
    @State private var isEditing = false
    @State private var editingText = ""

    private var hasAudio: Bool {
        TranscriptionDetailAccess.shouldShowPlayback(for: record)
    }

    private var kind: MediaSourceKind { record.resolvedSourceKind }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        Group {
            if isEditing {
                editCard
            } else {
                playerCard
            }
        }
        .task(id: record.id) {
            guard let mediaURL = record.managedMediaURL else {
                peaks = []
                playbackController.teardownPlayback()
                return
            }
            playbackController.load(url: mediaURL)
            // Peak extraction can decode large files — never on the main actor.
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? WaveformPeaksLoader.load(for: mediaURL)) ?? []
            }.value
            peaks = loaded
        }
        .onDisappear {
            playbackController.teardownPlayback()
        }
    }

    private var playerCard: some View {
        PlayerCardChrome(
            transcript: record.text,
            showsPlayer: hasAudio
        ) {
            VStack(alignment: .leading, spacing: 6) {
                metaRow
                timingRow
            }
        } player: {
            // Clock-dependent UI only — static chrome/meta/actions stay outside
            // the 0.25s playback observation graph.
            LibraryExpandedPlaybackControls(
                controller: playbackController,
                peaks: peaks,
                fallbackDuration: record.duration,
                playbackRate: $playbackRate,
                locale: locale
            )
        } actions: {
            actionsRow
        }
    }

    /// Inline transcript editing — mirrors PlayerCardChrome's container styling
    /// with the transcript body swapped for a TextEditor.
    private var editCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            metaRow

            TextEditor(text: $editingText)
                .font(AppTypography.transcriptBody)
                .lineSpacing(AppTypography.transcriptBodyLineSpacing)
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 96)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.contentBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
                .accessibilityIdentifier("library.editor.transcript")

            HStack(spacing: 8) {
                SecondaryButton(
                    title: localized("Cancel", locale: locale),
                    systemImage: "xmark",
                    action: { isEditing = false }
                )
                .accessibilityIdentifier("library.button.cancelEdit")

                Spacer(minLength: 8)

                SecondaryButton(
                    title: localized("Save", locale: locale),
                    systemImage: "checkmark",
                    action: {
                        isEditing = false
                        onSaveEdit?(editingText)
                    }
                )
                .accessibilityIdentifier("library.button.saveTranscript")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Meta

    private var metaRow: some View {
        HStack(spacing: 10) {
            Text(Self.timeFormatter.string(from: record.timestamp))
                .font(AppTypography.monoTime)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 64, alignment: .leading)
                .monospacedDigit()

            KindBadge(
                title: LibraryKindPresentation.badgeTitle(for: kind, locale: locale),
                systemImage: LibraryKindPresentation.systemImage(for: kind)
            )

            if let inserted = LibraryKindPresentation.insertedIntoCaption(
                appName: record.destinationAppName,
                locale: locale
            ) {
                Text(inserted)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            if record.userEditedAt != nil {
                Text(localized("Edited", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let caption = LibraryRetentionCaption.caption(
                retention: retention,
                hasAudio: hasAudio,
                sourceKind: kind,
                locale: locale
            ) {
                Text(caption)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 20)
    }

    // MARK: - Timing

    /// One caption line of pipeline stage latencies (and enhancement token usage)
    /// for instrumented dictations. Absent for pre-metrics records and media imports.
    @ViewBuilder
    private var timingRow: some View {
        if let metrics = record.pipelineMetrics, metrics.hasAnyStage {
            let captions = [
                PipelineTimingPresentation.stagesCaption(metrics, locale: locale),
                PipelineTimingPresentation.tokensCaption(metrics, locale: locale)
            ].compactMap { $0 }
            if !captions.isEmpty {
                Text(captions.joined(separator: " · "))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .monospacedDigit()
                    .lineLimit(2)
                    .accessibilityIdentifier("library.caption.pipelineTiming")
            }
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            SecondaryButton(
                title: localized("Copy", locale: locale),
                systemImage: "doc.on.doc",
                action: onCopy
            )
            if onSaveEdit != nil {
                SecondaryButton(
                    title: localized("Edit", locale: locale),
                    systemImage: "pencil",
                    action: {
                        editingText = record.text
                        isEditing = true
                    }
                )
                .accessibilityIdentifier("library.button.editTranscript")
            }
            ExportMenuButton(
                title: localized("Export", locale: locale),
                formats: TranscriptExportService.availableFormats(for: record),
                formatTitle: { $0.displayName(locale: locale) },
                onSelect: onExport
            )

            Spacer(minLength: 8)

            DestructiveGhostButton(
                title: localized("Delete", locale: locale),
                action: onDelete
            )
        }
    }
}

/// Narrow observer: only this subtree re-evaluates on playback clock ticks.
private struct LibraryExpandedPlaybackControls: View {
    let controller: MediaPlaybackController
    let peaks: [Float]
    let fallbackDuration: TimeInterval
    @Binding var playbackRate: Float
    let locale: Locale

    /// The loaded asset's duration is authoritative — the record's metadata duration
    /// can exceed the file's (trimmed trailing silence), which left the playhead
    /// stranded short of the end at playback finish. Metadata is only a placeholder
    /// until the player loads.
    private var effectiveDuration: Double {
        controller.duration > 0 ? controller.duration : fallbackDuration
    }

    private var playbackProgress: Double {
        let duration = effectiveDuration
        guard duration > 0 else { return 0 }
        return min(1, max(0, controller.currentTime / duration))
    }

    private var elapsedTotalLabel: String {
        let elapsed = controller.currentTime
        return "\(timestampLabel(for: elapsed)) / \(timestampLabel(for: effectiveDuration))"
    }

    var body: some View {
        PlayerRow(
            peaks: peaks,
            progress: playbackProgress,
            isPlaying: controller.isPlaying,
            elapsedTotalLabel: elapsedTotalLabel,
            rateLabel: LibraryPlaybackRate.label(for: playbackRate),
            onTogglePlay: {
                controller.togglePlayback()
                if controller.isPlaying {
                    controller.setRate(playbackRate)
                }
            },
            onSeek: { fraction in
                let duration = effectiveDuration
                guard duration > 0 else { return }
                controller.seek(to: fraction * duration)
            },
            onCycleRate: {
                let next = LibraryPlaybackRate.next(after: playbackRate)
                playbackRate = next
                if controller.isPlaying {
                    controller.setRate(next)
                }
            },
            rateHelp: localized("Playback speed", locale: locale)
        )
    }
}
