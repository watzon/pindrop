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
    let onInsertAgain: () -> Void
    let onExport: (TranscriptExportFormat) -> Void
    let onDelete: () -> Void

    @Environment(\.locale) private var locale

    @State private var playbackController = MediaPlaybackController()
    @State private var playbackRate: Float = 1.0
    @State private var peaks: [Float] = []

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
        PlayerCardChrome(
            transcript: record.text,
            showsPlayer: hasAudio
        ) {
            metaRow
        } player: {
            playerRow
        } actions: {
            actionsRow
        }
        .task(id: record.id) {
            guard let mediaURL = record.managedMediaURL else {
                peaks = []
                return
            }
            playbackController.load(url: mediaURL)
            peaks = (try? WaveformPeaksLoader.load(for: mediaURL)) ?? []
        }
        .onDisappear {
            if playbackController.isPlaying {
                playbackController.togglePlayback()
            }
        }
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

    // MARK: - Player

    private var playerRow: some View {
        HStack(spacing: 16) {
            Button {
                playbackController.togglePlayback()
                if playbackController.isPlaying {
                    playbackController.setRate(playbackRate)
                }
            } label: {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.contentBackground)
                            .offset(x: playbackController.isPlaying ? 0 : 1)
                    }
            }
            .buttonStyle(.plain)

            WaveformView(
                peaks: peaks,
                progress: playbackProgress,
                onSeek: { fraction in
                    let duration = max(playbackController.duration, record.duration)
                    guard duration > 0 else { return }
                    playbackController.seek(to: fraction * duration)
                }
            )
            .frame(maxWidth: .infinity)

            Text(elapsedTotalLabel)
                .font(AppTypography.monoTime)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
                .fixedSize()

            Button {
                let next = LibraryPlaybackRate.next(after: playbackRate)
                playbackRate = next
                if playbackController.isPlaying {
                    playbackController.setRate(next)
                }
            } label: {
                Text(LibraryPlaybackRate.label(for: playbackRate))
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .overlay(
                        Capsule().strokeBorder(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(localized("Playback speed", locale: locale))
        }
        .frame(height: 44)
    }

    private var playbackProgress: Double {
        let duration = max(playbackController.duration, record.duration)
        guard duration > 0 else { return 0 }
        return min(1, max(0, playbackController.currentTime / duration))
    }

    private var elapsedTotalLabel: String {
        let elapsed = playbackController.currentTime
        let total = max(playbackController.duration, record.duration)
        return "\(timestampLabel(for: elapsed)) / \(timestampLabel(for: total))"
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            SecondaryButton(
                title: localized("Copy", locale: locale),
                systemImage: "doc.on.doc",
                action: onCopy
            )
            SecondaryButton(
                title: localized("Insert again", locale: locale),
                systemImage: "arrow.uturn.backward",
                action: onInsertAgain
            )
            Menu {
                ForEach(TranscriptExportService.availableFormats(for: record), id: \.rawValue) { format in
                    Button(format.displayName(locale: locale)) {
                        onExport(format)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                    Text(localized("Export", locale: locale))
                        .font(AppTypography.label)
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColors.contentBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 8)

            DestructiveGhostButton(
                title: localized("Delete", locale: locale),
                action: onDelete
            )
        }
    }
}
