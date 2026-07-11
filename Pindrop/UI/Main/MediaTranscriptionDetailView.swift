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
import SwiftData
import SwiftUI

struct MediaTranscriptionDetailView: View {
    let record: TranscriptionRecord
    let folders: [MediaFolder]
    let onBack: () -> Void
    let onAssignFolder: (MediaFolder) -> Void
    let onRemoveFromFolder: () -> Void
    let onAssignSpeakerProfile: (String, UUID) -> Void
    let onCreateSpeakerProfile: (String, String, String?) -> Bool
    let onDelete: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var knownProfiles: [ParticipantProfile]
    @State private var playbackController = MediaPlaybackController()
    @State private var followPlayback = true
    @State private var playbackRate: Float = 1.0
    @State private var speakerLabelsByID: [String: String] = [:]
    @State private var creatingProfileForSpeakerID: String?
    @State private var newProfileName = ""
    @State private var newProfileNotes = ""
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

    // Decoded ONCE per record/label change and cached: `record.diarizedSegments`
    // JSON-decodes the whole payload, and the playback clock re-evaluates this view
    // 4×/sec — computing segments per tick made long transcripts visibly laggy.
    @State private var cachedSegments: [DiarizedTranscriptSegment] = []
    @State private var cachedSegmentIDs: [String] = []

    private var segments: [DiarizedTranscriptSegment] { cachedSegments }

    private func rebuildSegmentCache() {
        let displayed = record.diarizedSegments.map { segment in
            displayedSegment(segment)
        }
        cachedSegments = displayed
        cachedSegmentIDs = displayed.enumerated().map { index, segment in
            "\(segment.speakerId)-\(index)-\(segment.startTime)"
        }
    }

    private func displayedSegment(
        _ segment: DiarizedTranscriptSegment
    ) -> DiarizedTranscriptSegment {
            let assignedProfileName = segment.speakerProfileID.flatMap { profileID in
                knownProfiles.first { $0.id == profileID }?.displayName
            }
            let speakerLabel = assignedProfileName ?? speakerLabelsByID[segment.speakerId]
            guard let speakerLabel,
                  !speakerLabel.isEmpty,
                  speakerLabel != segment.speakerLabel else {
                return segment
            }

            return DiarizedTranscriptSegment(
                speakerId: segment.speakerId,
                speakerLabel: speakerLabel,
                speakerProfileID: segment.speakerProfileID,
                speakerEmbedding: segment.speakerEmbedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: segment.text
            )
    }

    /// Every distinct speaker, INCLUDING unnamed ones — fresh diarization arrives
    /// with raw IDs and empty labels, and hiding those hid the legend exactly when
    /// renaming matters most. Unnamed speakers get numbered fallbacks.
    private var participants: [(key: String, speakerID: String, label: String)] {
        var seen = Set<String>()
        var unnamedCount = 0
        var result: [(key: String, speakerID: String, label: String)] = []
        for segment in cachedSegments {
            let key = LibrarySpeakerColor.canonicalKey(
                speakerId: segment.speakerId,
                speakerLabel: segment.speakerLabel
            )
            guard seen.insert(key).inserted else { continue }
            let label = segment.speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty {
                unnamedCount += 1
                result.append((key, segment.speakerId, "\(localized("Speaker", locale: locale)) \(unnamedCount)"))
            } else {
                result.append((key, segment.speakerId, label))
            }
        }
        return result
    }

    private var sortedProfiles: [ParticipantProfile] {
        knownProfiles.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func assignSpeaker(speakerID: String, to profile: ParticipantProfile) {
        guard !speakerID.isEmpty else { return }
        speakerLabelsByID[speakerID] = profile.displayName
        onAssignSpeakerProfile(speakerID, profile.id)
    }

    private var isCreateProfileSheetPresented: Binding<Bool> {
        Binding(
            get: { creatingProfileForSpeakerID != nil },
            set: { isPresented in
                if !isPresented {
                    resetNewProfileForm()
                }
            }
        )
    }

    /// One linear scan per playback tick (hoisted in transcriptSection — never per
    /// row). NOT a binary search: diarized segments can be out of order and can
    /// overlap when speakers talk over each other, so "first segment containing t"
    /// in display order is the correct pick.
    private var activeSegmentID: String? {
        let time = playbackController.currentTime
        guard let index = cachedSegments.firstIndex(where: {
            time >= $0.startTime && time < $0.endTime
        }) else {
            return nil
        }
        return cachedSegmentIDs[index]
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
        GeometryReader { geo in
            if geo.size.width >= 960 {
                // Wide windows: breadcrumb/title and the media rail stay put;
                // only the transcript pane scrolls.
                VStack(alignment: .leading, spacing: 24) {
                    // Spec §8: breadcrumb → title gap is 16 pt (not the section 24 pt rhythm).
                    VStack(alignment: .leading, spacing: 16) {
                        breadcrumb
                        titleBlock
                    }

                    HStack(alignment: .top, spacing: 32) {
                        // The rail scrolls only if a short window can't fit it.
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                mediaAndSummaryColumn
                            }
                            .padding(.bottom, 40)
                        }
                        .frame(width: 480)

                        ScrollView(.vertical, showsIndicators: false) {
                            transcriptSection
                                .padding(.bottom, 40)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            breadcrumb
                            titleBlock
                        }

                        mediaAndSummaryColumn
                        transcriptSection
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(AppColors.contentBackground)
        .task(id: record.id) {
            speakerLabelsByID = currentSpeakerLabelsByID()
            rebuildSegmentCache()
            guard let mediaURL = record.managedMediaURL else {
                peaks = []
                return
            }
            playbackController.load(url: mediaURL)
            // Peak extraction can decode the whole file — never on the main actor.
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? WaveformPeaksLoader.load(for: mediaURL)) ?? []
            }.value
            peaks = loaded
        }
        .onChange(of: record.diarizationSegmentsJSON) { _, _ in
            speakerLabelsByID = currentSpeakerLabelsByID()
            rebuildSegmentCache()
        }
        .onChange(of: speakerLabelsByID) { _, _ in
            rebuildSegmentCache()
        }
        .onChange(of: knownProfiles.map(\.updatedAt)) { _, _ in
            rebuildSegmentCache()
        }
        .sheet(isPresented: isCreateProfileSheetPresented) {
            SpeakerProfileCreationSheet(
                name: $newProfileName,
                notes: $newProfileNotes,
                locale: locale,
                onCancel: resetNewProfileForm,
                onCreate: createAndAssignProfile
            )
        }
    }

    /// Video, player bar, and summary — the left rail in two-column layout,
    /// inline sections in single-column.
    @ViewBuilder
    private var mediaAndSummaryColumn: some View {
        if hasMedia {
            if playbackController.hasVideoTrack {
                videoSurface
            }
            playerBarCard
        }
        if record.hasSummary, let summary = record.aiSummary {
            summaryBlock(summary)
        }
        if showsSpeakerLanes, !participants.isEmpty {
            participantsFooter
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .flipsForRightToLeftLayoutDirection(true)
                Text(localized("Library", locale: locale))
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
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

                ExportMenuButton(
                    title: localized("Export", locale: locale),
                    formats: TranscriptExportService.availableFormats(for: record),
                    formatTitle: { $0.displayName(locale: locale) },
                    onSelect: { exportTranscript(format: $0) }
                )
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

    // MARK: - Video surface (imported video)

    private var videoSurface: some View {
        AVPlayerViewRepresentable(player: playbackController.player)
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
    }

    // MARK: - Player bar

    private var playerBarCard: some View {
        PlayerRow(
            peaks: peaks,
            progress: playbackProgress,
            isPlaying: playbackController.isPlaying,
            elapsedTotalLabel: elapsedTotalLabel,
            rateLabel: LibraryPlaybackRate.label(for: playbackRate),
            onTogglePlay: {
                playbackController.togglePlayback()
                if playbackController.isPlaying {
                    playbackController.setRate(playbackRate)
                }
            },
            onSeek: { fraction in
                let duration = max(playbackController.duration, record.duration)
                guard duration > 0 else { return }
                playbackController.seek(to: fraction * duration)
            },
            onCycleRate: {
                let next = LibraryPlaybackRate.next(after: playbackRate)
                playbackRate = next
                if playbackController.isPlaying {
                    playbackController.setRate(next)
                }
            },
            rateHelp: localized("Playback speed", locale: locale)
        )
        .padding(16)
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
        // Hoisted: one binary search per evaluation, not one per row.
        let activeID = activeSegmentID

        return VStack(alignment: .leading, spacing: 12) {
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
                        ForEach(cachedSegments.indices, id: \.self) { index in
                            turnRow(
                                cachedSegments[index],
                                isActive: cachedSegmentIDs[index] == activeID
                            )
                            .id(cachedSegmentIDs[index])
                        }
                    }
                    .onChange(of: activeSegmentID) { _, identifier in
                        guard followPlayback, let identifier else { return }
                        withAnimation(reduceMotion ? nil : AppTheme.Animation.normal) {
                            proxy.scrollTo(identifier, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func turnRow(_ segment: DiarizedTranscriptSegment, isActive: Bool) -> some View {
        let active = isActive
        let speakerColor = LibrarySpeakerColor.color(
            speakerId: segment.speakerId,
            speakerLabel: segment.speakerLabel
        )

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
            // Spec §8: no horizontal content padding (timestamp stays on the left rule).
            // Active pill gets breathing room via background inset only.
            .padding(.vertical, 10)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.accentBackground)
                        .padding(.horizontal, -8)
                        .padding(.vertical, -2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appAnimation(.fast, value: active)
        .contextMenu {
            if !segment.speakerId.isEmpty {
                speakerProfileMenu(speakerID: segment.speakerId)
            }
        }
    }

    private var participantsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Speakers", locale: locale))
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            ForEach(participants, id: \.key) { participant in
                let speakerID = participant.speakerID.isEmpty
                    ? participant.key
                    : participant.speakerID
                HStack(spacing: 8) {
                    Circle()
                        .fill(LibrarySpeakerColor.color(for: participant.key))
                        .frame(width: 7, height: 7)
                    Text(participant.label)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(sortedProfiles) { profile in
                            Button(profile.displayName) {
                                assignSpeaker(speakerID: speakerID, to: profile)
                            }
                        }
                        if !sortedProfiles.isEmpty {
                            Divider()
                        }
                        Button(localized("Create New Profile…", locale: locale)) {
                            creatingProfileForSpeakerID = speakerID
                        }
                    } label: {
                        Text(localized("Assign Speaker", locale: locale))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private func speakerProfileMenu(speakerID: String) -> some View {
        Menu(localized("Assign Speaker", locale: locale)) {
            ForEach(sortedProfiles) { profile in
                Button(profile.displayName) {
                    assignSpeaker(speakerID: speakerID, to: profile)
                }
            }
            if !sortedProfiles.isEmpty {
                Divider()
            }
            Button(localized("Create New Profile…", locale: locale)) {
                creatingProfileForSpeakerID = speakerID
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
        // Reads the record directly: this runs before the cache is (re)built.
        for segment in record.diarizedSegments {
            guard labelsByID[segment.speakerId] == nil else { continue }
            let label = segment.speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            labelsByID[segment.speakerId] = label
        }
        return labelsByID
    }

    private func createAndAssignProfile() {
        guard let speakerID = creatingProfileForSpeakerID else { return }
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedNotes = newProfileNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let didCreate = onCreateSpeakerProfile(
            speakerID,
            trimmedName,
            trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        guard didCreate else { return }
        speakerLabelsByID[speakerID] = trimmedName
        resetNewProfileForm()
    }

    private func resetNewProfileForm() {
        creatingProfileForSpeakerID = nil
        newProfileName = ""
        newProfileNotes = ""
    }

}

private struct SpeakerProfileCreationSheet: View {
    @Binding var name: String
    @Binding var notes: String
    let locale: Locale
    let onCancel: () -> Void
    let onCreate: () -> Void

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Create Speaker Profile", locale: locale))
                .font(AppTypography.title)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Name", locale: locale))
                    .font(AppTypography.label)
                TextField(localized("Name", locale: locale), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Notes", locale: locale))
                    .font(AppTypography.label)
                TextEditor(text: $notes)
                    .font(AppTypography.body)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(AppColors.contentBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    }
            }

            HStack {
                Spacer()
                Button(localized("Cancel", locale: locale), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(localized("Create", locale: locale), action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 420)
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
        let clamped = max(0, seconds)
        // Optimistic: update the published time immediately so the active-row
        // highlight follows the click; the periodic observer only reports the
        // post-seek time a beat later (and not reliably while paused).
        currentTime = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func observeTime() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                // @Observable fires on every assignment, equal or not — skip
                // no-op writes so a paused player doesn't invalidate observers 4×/sec.
                let seconds = time.seconds.isFinite ? time.seconds : 0
                if abs(seconds - self.currentTime) >= 0.01 {
                    self.currentTime = seconds
                }
                let playing = self.player.rate > 0
                if playing != self.isPlaying {
                    self.isPlaying = playing
                }
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
