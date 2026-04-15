//
//  MediaTranscriptionDetailView.swift
//  Pindrop
//
//  Unified transcription detail view used by both History and the Transcribe
//  tab, for voice/meeting/imported/media records. Layout inspired by the
//  Pencil reference: header with title + status, transcript with active-line
//  highlight, bottom playback bar, right sidebar with preview + structured
//  details + actions row + summary placeholder.
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
    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    @State private var playbackRate: Float = 1.0
    @State private var showCopiedToast = false
    @State private var speakerLabelsByID: [String: String] = [:]
    @State private var editingSpeakerID: String?
    @State private var editedSpeakerLabel = ""

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

    private var hasMedia: Bool { record.managedMediaURL != nil }
    private var wordCount: Int { record.text.split(separator: " ").count }

    private var kindInfo: (label: String, color: Color, icon: String) {
        switch record.resolvedSourceKind {
        case .voiceRecording: return ("Voice", AppColors.accent, "mic.fill")
        case .manualCapture:  return ("Meeting", AppColors.success, "person.2.fill")
        case .importedFile:   return ("Audio", AppColors.processing, "headphones")
        case .webLink:        return ("Video", AppColors.processing, "film")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .padding(.bottom, AppTheme.Spacing.lg)
                .background(AppColors.contentBackground)

            HStack(alignment: .top, spacing: AppTheme.Spacing.xl) {
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                sidebar
                    .frame(width: 340, alignment: .topLeading)
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .background(AppColors.contentBackground)
        .task(id: record.id) {
            if let mediaURL = record.managedMediaURL {
                playbackController.load(url: mediaURL)
            }
            speakerLabelsByID = currentSpeakerLabelsByID()
        }
        .onChange(of: record.diarizationSegmentsJSON) { _, _ in
            speakerLabelsByID = currentSpeakerLabelsByID()
        }
        .onChange(of: playbackController.currentTime) { _, newValue in
            if !isDraggingSlider {
                sliderValue = newValue
            }
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
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(AppTypography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(Capsule(style: .continuous).fill(AppColors.accent))
                    .padding(.bottom, AppTheme.Spacing.xxl)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(AppColors.surfaceBackground)
                    )
                    .overlay(
                        Circle().strokeBorder(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Back")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(displayTitle)
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    kindBadge
                }

                Text(subtitleText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Toggle(isOn: $followPlayback) {
                Text("Follow playback").font(AppTypography.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private var displayTitle: String {
        if let name = record.sourceDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        switch record.resolvedSourceKind {
        case .manualCapture: return "Meeting Recording"
        case .voiceRecording: return "Voice Transcription"
        case .importedFile: return "Imported Audio"
        case .webLink: return "Web Transcription"
        }
    }

    private var subtitleText: String {
        var parts: [String] = [kindInfo.label]
        parts.append(record.timestamp.formatted(date: .abbreviated, time: .shortened))
        if record.duration > 0 {
            parts.append(formatDuration(record.duration))
        }
        return parts.joined(separator: " · ")
    }

    private var kindBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: kindInfo.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(kindInfo.label)
                .font(AppTypography.tiny)
        }
        .foregroundStyle(kindInfo.color)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(kindInfo.color.opacity(0.12)))
    }

    // MARK: - Left column (transcript + player)

    private var leftColumn: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            transcriptArea
                .frame(maxHeight: .infinity)

            bottomPlayerBar
        }
    }

    private var transcriptArea: some View {
        Group {
            if segments.isEmpty {
                ScrollView {
                    Text(record.text)
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(AppTheme.Spacing.xl)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            ForEach(Array(displayedSegments.enumerated()), id: \.offset) { index, segment in
                                segmentRow(segment, index: index)
                                    .id(segmentIdentifier(segment, index: index))
                            }
                        }
                        .padding(AppTheme.Spacing.lg)
                    }
                    .onChange(of: activeSegmentID) { _, identifier in
                        guard followPlayback, let identifier else { return }
                        withAnimation(AppTheme.Animation.normal) {
                            proxy.scrollTo(identifier, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous),
            style: AppColors.border
        )
    }

    private func segmentRow(_ segment: DiarizedTranscriptSegment, index: Int) -> some View {
        let active = isActive(segment, index: index)
        return Button {
            playbackController.seek(to: segment.startTime)
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Text(timestampLabel(for: segment.startTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(active ? AppColors.accent : AppColors.textTertiary)
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    if !segment.speakerLabel.isEmpty {
                        Text(segment.speakerLabel)
                            .font(AppTypography.tiny)
                            .foregroundStyle(active ? AppColors.accent : AppColors.textTertiary)
                    }

                    Text(segment.text)
                        .font(.system(size: 15, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? AppColors.textPrimary : AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(active ? AppColors.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(active ? AppColors.accent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.fast, value: active)
    }

    private var bottomPlayerBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Play/pause circle
            Button {
                playbackController.togglePlayback()
                // Re-apply rate since AVPlayer resets to 1.0 after pause().
                if playbackController.isPlaying {
                    playbackController.setRate(playbackRate)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(hasMedia ? AppColors.accent : AppColors.accent.opacity(0.3))
                        .frame(width: 36, height: 36)
                    Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: playbackController.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasMedia)

            // Scrubber
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
            .tint(AppColors.accent)
            .disabled(!hasMedia)

            Text("\(timestampLabel(for: sliderValue)) / \(timestampLabel(for: playbackController.duration))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        playbackRate = Float(rate)
                        if playbackController.isPlaying {
                            playbackController.setRate(Float(rate))
                        }
                    } label: {
                        HStack {
                            Text(rateLabel(for: Float(rate)))
                            if abs(playbackRate - Float(rate)) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(rateLabel(for: playbackRate))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(minWidth: 36)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(AppColors.elevatedSurface)
                    )
                    .overlay(
                        Capsule().strokeBorder(AppColors.border, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                exportTranscript()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(AppTypography.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: AppColors.border
        )
    }

    private func rateLabel(for rate: Float) -> String {
        let rounded = (rate * 100).rounded() / 100
        if rounded == 1.0 { return "1x" }
        if rounded == rounded.rounded() {
            return "\(Int(rounded))x"
        }
        return String(format: "%.2gx", rounded)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            mediaPreviewCard
                .transaction { $0.animation = nil }

            detailsCard

            if !participants.isEmpty {
                participantsCard
            }

            actionsRow

            summaryCard

            Spacer()
        }
    }

    @ViewBuilder
    private var mediaPreviewCard: some View {
        if let mediaURL = record.managedMediaURL {
            if playbackController.hasVideoTrack {
                AVPlayerViewRepresentable(player: playbackController.player)
                    .frame(height: 180)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .fill(AppColors.elevatedSurface)
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: kindInfo.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(kindInfo.color.opacity(0.9))
                        Text(mediaURL.lastPathComponent)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                )
            }
        } else {
            MessageCardView(
                title: "Media unavailable",
                message: "The managed media file could not be found on disk.",
                icon: "exclamationmark.triangle.fill",
                tint: AppColors.warning
            )
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Details")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: AppTheme.Spacing.sm) {
                detailRow("Type", value: kindInfo.label)
                detailRow("Duration", value: record.duration > 0 ? formatDuration(record.duration) : "—")
                if !record.modelUsed.isEmpty {
                    detailRow("Model", value: record.modelUsed)
                }
                if let enhancedWith = record.enhancedWith {
                    detailRow("Enhanced", value: enhancedWith)
                }
                detailRow("Word Count", value: "\(wordCount)")
                detailRow("Created", value: record.timestamp.formatted(date: .abbreviated, time: .shortened))
                detailRow("Folder", value: record.folder?.name ?? "Unfiled")

                if let originalSourceURL = record.originalSourceURL,
                   let url = URL(string: originalSourceURL),
                   record.resolvedSourceKind == .webLink {
                    Divider().padding(.vertical, 2)
                    Link(destination: url) {
                        Label("Open original link", systemImage: "arrow.up.right.square")
                            .font(AppTypography.caption)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: AppColors.border
        )
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            actionButton(title: "Copy All", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
                flashCopied()
            }

            Menu {
                Button("Copy as Plain Text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                    flashCopied()
                }
                Button("Copy with Timestamps") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcriptWithTimestamps(), forType: .string)
                    flashCopied()
                }
                Divider()
                if let mediaURL = record.managedMediaURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([mediaURL])
                    }
                }
            } label: {
                actionButtonLabel(title: "Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                if folders.isEmpty {
                    Button("No folders yet") {}.disabled(true)
                } else {
                    ForEach(folders) { folder in
                        Button(folder.name) { onAssignFolder(folder) }
                    }
                }
                if record.folder != nil {
                    Divider()
                    Button("Remove from Folder", role: .destructive) {
                        onRemoveFromFolder()
                    }
                }
                Divider()
                Button("Delete Transcription", role: .destructive) {
                    onDelete()
                }
            } label: {
                actionButtonLabel(title: "More", systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(participants, id: \.speakerID) { participant in
                    HStack {
                        Text(participant.label)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: AppTheme.Spacing.sm)

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
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: AppColors.border
        )
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(AppTypography.caption)
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                Text("AI Summary")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Text(summaryPreviewText)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppColors.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppColors.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var summaryPreviewText: String {
        // Placeholder until we generate real summaries: show the opening
        // sentences of the transcript so the card has real content to reveal.
        let trimmed = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "A summary will appear here once generated."
        }
        let sentences = trimmed.split(omittingEmptySubsequences: true) { ".!?".contains($0) }
        let preview = sentences.prefix(2).joined(separator: ". ")
        if preview.isEmpty {
            return String(trimmed.prefix(240))
        }
        return preview.count > 240 ? String(preview.prefix(240)) + "…" : preview + "."
    }

    // MARK: - Actions

    private func transcriptWithTimestamps() -> String {
        guard !displayedSegments.isEmpty else { return record.text }
        return displayedSegments.map { segment -> String in
            let ts = timestampLabel(for: segment.startTime)
            let speaker = segment.speakerLabel.isEmpty ? "" : "\(segment.speakerLabel) "
            return "[\(ts)] \(speaker)\(segment.text)"
        }.joined(separator: "\n")
    }

    private func exportTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (record.sourceDisplayName ?? "transcript") + ".txt"
        if panel.runModal() == .OK, let url = panel.url {
            let content = displayedSegments.isEmpty ? record.text : transcriptWithTimestamps()
            try? content.write(to: url, atomically: true, encoding: .utf8)
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

    private func flashCopied() {
        withAnimation(AppTheme.Animation.fast) { showCopiedToast = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(AppTheme.Animation.fast) { showCopiedToast = false }
        }
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
