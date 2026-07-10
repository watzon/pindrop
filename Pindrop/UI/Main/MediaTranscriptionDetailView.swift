//
//  MediaTranscriptionDetailView.swift
//  Pindrop
//
//  Meeting / media / voice detail page (U3 scorched-earth restyle, spec §8).
//

import AVFoundation
import AVKit
import AppKit
import Foundation
import Observation
import SwiftUI

struct MediaTranscriptionDetailView: View {
    let record: TranscriptionRecord
    let folders: [MediaFolder]
    let onBack: () -> Void
    let onAssignFolder: (MediaFolder) -> Void
    let onRemoveFromFolder: () -> Void
    let onRenameSpeakers: ([String: String]) -> Void
    let onDelete: () -> Void

    @Environment(\.locale) private var locale

    @State private var playbackController = MediaPlaybackController()
    @State private var followPlayback = true
    @State private var playbackRate: Float = 1.0
    @State private var speakerLabelsByID: [String: String] = [:]
    @State private var editingSpeakerID: String?
    @State private var editedSpeakerLabel = ""
    @State private var peaks: [Float] = []

    private static let detailTitleMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 30, weight: .medium, lineHeight: 36
    )
    private static let turnBodyMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 15, weight: .regular, lineHeight: 23
    )
    private static let summaryBodyMetrics = TypographyRoleMetrics(
        family: .newsreader, size: 15, weight: .regular, lineHeight: 23
    )

    private var segments: [DiarizedTranscriptSegment] {
        record.diarizedSegments
    }

    private var displayedSegments: [DiarizedTranscriptSegment] {
        segments.map { segment in
            guard let speakerLabel = speakerLabelsByID[segment.speakerId],
                  !speakerLabel.isEmpty,
                  speakerLabel != segment.speakerLabel else {
                return segment
            }

            return DiarizedTranscriptSegment(
                speakerId: segment.speakerId,
                speakerLabel: speakerLabel,
                speakerEmbedding: segment.speakerEmbedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: segment.text
            )
        }
    }

    private var participants: [(speakerID: String, label: String)] {
        var seen = Set<String>()
        return displayedSegments.compactMap { segment in
            guard !seen.contains(segment.speakerId) else { return nil }
            seen.insert(segment.speakerId)
            let label = segment.speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            return (segment.speakerId, label)
        }
    }

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { editingSpeakerID != nil },
            set: { isPresented in
                if !isPresented {
                    editingSpeakerID = nil
                    editedSpeakerLabel = ""
                }
            }
        )
    }

    private var activeSegmentID: String? {
        guard let index = segments.firstIndex(where: {
            playbackController.currentTime >= $0.startTime && playbackController.currentTime < $0.endTime
        }) else {
            return nil
        }
        return segmentIdentifier(segments[index], index: index)
    }

    private var hasMedia: Bool { TranscriptionDetailAccess.shouldShowPlayback(for: record) }
    private var showsSpeakerLanes: Bool { !segments.isEmpty }

    private static let metaDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                breadcrumb
                titleBlock
                if hasMedia {
                    playerBarCard
                }
                if record.hasSummary, let summary = record.aiSummary {
                    summaryBlock(summary)
                }
                transcriptSection
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.contentBackground)
        .task(id: record.id) {
            if let mediaURL = record.managedMediaURL {
                playbackController.load(url: mediaURL)
                peaks = (try? WaveformPeaksLoader.load(for: mediaURL)) ?? []
            } else {
                peaks = []
            }
            speakerLabelsByID = currentSpeakerLabelsByID()
        }
        .onChange(of: record.diarizationSegmentsJSON) { _, _ in
            speakerLabelsByID = currentSpeakerLabelsByID()
        }
        .alert(localized("Edit", locale: locale), isPresented: isRenameAlertPresented) {
            TextField("", text: $editedSpeakerLabel)
            Button(localized("Cancel", locale: locale), role: .cancel) {
                editingSpeakerID = nil
                editedSpeakerLabel = ""
            }
            Button(localized("Save", locale: locale)) {
                saveEditedSpeakerLabel()
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(localized("Library", locale: locale))
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 0)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(Self.detailTitleMetrics.font)
                .tracking(-0.015 * 30)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Text(Self.metaDateFormatter.string(from: record.timestamp))
                    .font(AppTypography.monoTime)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()

                Text("·")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textTertiary)

                if record.duration > 0 {
                    Text(formatDuration(record.duration))
                        .font(AppTypography.monoTime)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }

                if showsSpeakerLanes, record.speakerCount > 0 {
                    Text("·")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)

                    Text(speakersMetaLabel)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 12)

                SecondaryButton(
                    title: localized("Copy", locale: locale),
                    systemImage: "doc.on.doc"
                ) {
                    NotificationCenter.default.post(
                        name: .copyTextWithUndo,
                        object: nil,
                        userInfo: ["text": record.text]
                    )
                }

                Menu {
                    ForEach(TranscriptExportService.availableFormats(for: record), id: \.rawValue) { format in
                        Button(format.displayName(locale: locale)) {
                            exportTranscript(format: format)
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
            }
        }
    }

    private var speakersMetaLabel: String {
        let count = record.speakerCount
        if count == 1 {
            return localized("1 speaker", locale: locale)
        }
        return String(format: localized("%d speakers", locale: locale), count)
    }

    private var displayTitle: String {
        if let preferredTitle = record.preferredTitle,
           !preferredTitle.isEmpty {
            return preferredTitle
        }
        if let name = record.sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        switch record.resolvedSourceKind {
        case .manualCapture:
            return localized("Meeting Recording", locale: locale)
        case .voiceRecording:
            return localized("Voice Transcription", locale: locale)
        case .importedFile:
            return localized("Imported Audio", locale: locale)
        case .webLink:
            return localized("Web Transcription", locale: locale)
        }
    }

    // MARK: - Player bar

    private var playerBarCard: some View {
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
        }
        .padding(16)
        .frame(height: 44 + 32)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
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

    // MARK: - Summary

    private func summaryBlock(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("SUMMARY", locale: locale))
                    .font(AppTypography.badge)
                    .tracking(0.08 * 11)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)

                Text(summary)
                    .font(Self.summaryBodyMetrics.font)
                    .lineSpacing(Self.summaryBodyMetrics.lineSpacing)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: localized("Transcript", locale: locale),
                trailing: hasMedia
                    ? localized("click a line to jump playback", locale: locale)
                    : nil,
                isFirst: true
            )

            if segments.isEmpty {
                Text(record.text)
                    .font(Self.turnBodyMetrics.font)
                    .lineSpacing(Self.turnBodyMetrics.lineSpacing)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedSegments.enumerated()), id: \.offset) { index, segment in
                            turnRow(segment, index: index)
                                .id(segmentIdentifier(segment, index: index))
                        }
                    }
                    .onChange(of: activeSegmentID) { _, identifier in
                        guard followPlayback, let identifier else { return }
                        withAnimation(AppTheme.Animation.normal) {
                            proxy.scrollTo(identifier, anchor: .center)
                        }
                    }
                }
            }

            if showsSpeakerLanes, !participants.isEmpty {
                participantsFooter
                    .padding(.top, 16)
            }
        }
    }

    private func turnRow(_ segment: DiarizedTranscriptSegment, index: Int) -> some View {
        let active = isActive(segment, index: index)
        let speakerKey = segment.speakerId.isEmpty ? segment.speakerLabel : segment.speakerId
        let speakerColor = LibrarySpeakerColor.color(for: speakerKey)

        return Button {
            if hasMedia {
                playbackController.seek(to: segment.startTime)
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(timestampLabel(for: segment.startTime))
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(active ? AppColors.accent : AppColors.textTertiary)
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 3)
                    .monospacedDigit()

                if showsSpeakerLanes {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speakerColor)
                            .frame(width: 7, height: 7)
                        Text(segment.speakerLabel.isEmpty
                             ? localized("Speaker", locale: locale)
                             : segment.speakerLabel)
                            .font(AppTypography.labelSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 92, alignment: .leading)
                    .padding(.top, 2)
                }

                Text(segment.text)
                    .font(Self.turnBodyMetrics.font)
                    .lineSpacing(Self.turnBodyMetrics.lineSpacing)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? AppColors.accentBackground : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.fast, value: active)
        .contextMenu {
            if !segment.speakerId.isEmpty {
                Button(localized("Edit", locale: locale)) {
                    editingSpeakerID = segment.speakerId
                    editedSpeakerLabel = segment.speakerLabel
                }
            }
        }
    }

    private var participantsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Speakers", locale: locale))
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            ForEach(participants, id: \.speakerID) { participant in
                HStack(spacing: 8) {
                    Circle()
                        .fill(LibrarySpeakerColor.color(for: participant.speakerID))
                        .frame(width: 7, height: 7)
                    Text(participant.label)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Button(localized("Edit", locale: locale)) {
                        editingSpeakerID = participant.speakerID
                        editedSpeakerLabel = participant.label
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func exportTranscript(format: TranscriptExportFormat) {
        do {
            try TranscriptExportService.presentSavePanel(for: record, format: format)
        } catch TranscriptExportService.ExportError.cancelled {
            // User dismissed the panel.
        } catch {
            Log.app.error("Export failed: \(error.localizedDescription)")
        }
    }

    private func currentSpeakerLabelsByID() -> [String: String] {
        var labelsByID: [String: String] = [:]
        for segment in segments {
            guard labelsByID[segment.speakerId] == nil else { continue }
            let label = segment.speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            labelsByID[segment.speakerId] = label
        }
        return labelsByID
    }

    private func saveEditedSpeakerLabel() {
        guard let speakerID = editingSpeakerID else { return }
        let trimmedLabel = editedSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return }

        speakerLabelsByID[speakerID] = trimmedLabel
        onRenameSpeakers(speakerLabelsByID)

        editingSpeakerID = nil
        editedSpeakerLabel = ""
    }

    private func isActive(_ segment: DiarizedTranscriptSegment, index: Int) -> Bool {
        activeSegmentID == segmentIdentifier(segment, index: index)
    }

    private func segmentIdentifier(_ segment: DiarizedTranscriptSegment, index: Int) -> String {
        "\(segment.speakerId)-\(index)-\(segment.startTime)"
    }
}

/// NSViewRepresentable wrapping AVPlayerView directly. We avoid
/// AVKit.VideoPlayer (SwiftUI) because on macOS 26 its runtime metadata
/// instantiation can crash with `getSuperclassMetadata` under certain
/// view-tree shapes. Driving AVPlayerView through AppKit sidesteps the
/// problematic `_AVKit_SwiftUI` generic path entirely.
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct TranscriptionThumbnailView: View {
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

@MainActor
@Observable
final class MediaPlaybackController {
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

    func setRate(_ rate: Float) {
        player.rate = rate
        isPlaying = rate > 0
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

func formatDuration(_ duration: TimeInterval) -> String {
    timestampLabel(for: duration)
}

func timestampLabel(for duration: TimeInterval) -> String {
    guard duration.isFinite, duration > 0 else { return "0:00" }
    let totalSeconds = Int(duration.rounded(.down))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return "\(minutes):" + String(format: "%02d", seconds)
}
