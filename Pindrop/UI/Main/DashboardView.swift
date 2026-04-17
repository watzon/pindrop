//
//  DashboardView.swift
//  Pindrop
//
//  Dashboard home view with hero, stats, quick actions, and recent activity
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @State private var hasDismissedHotkeyReminder: Bool
    @State private var showingActionMenu = false
    @State private var selectedTranscriptionID: PersistentIdentifier?
    @State private var detailRecord: TranscriptionRecord?
    @State private var pendingDeletionRecord: TranscriptionRecord?
    @State private var errorMessage: String?
    @ObservedObject private var indicatorState: FloatingIndicatorState
    @ObservedObject private var settingsStore: SettingsStore

    @Query private var mediaFolders: [MediaFolder]

    private var folders: [MediaFolder] {
        mediaFolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var historyStore: HistoryStore {
        HistoryStore(modelContext: modelContext)
    }

    var onOpenHotkeys: (() -> Void)?
    var onViewAllHistory: (() -> Void)?
    var onNewTranscription: (() -> Void)?
    var onTranscribeFile: (() -> Void)?
    var onRecordMeeting: (() -> Void)?
    var onNewNote: (() -> Void)?

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(
        floatingIndicatorState: FloatingIndicatorState? = nil,
        settingsStore: SettingsStore? = nil,
        onOpenHotkeys: (() -> Void)? = nil,
        onViewAllHistory: (() -> Void)? = nil,
        onNewTranscription: (() -> Void)? = nil,
        onTranscribeFile: (() -> Void)? = nil,
        onRecordMeeting: (() -> Void)? = nil,
        onNewNote: (() -> Void)? = nil
    ) {
        self._indicatorState = ObservedObject(wrappedValue: floatingIndicatorState ?? FloatingIndicatorState())
        self._settingsStore = ObservedObject(wrappedValue: settingsStore ?? SettingsStore())
        self.onOpenHotkeys = onOpenHotkeys
        self.onViewAllHistory = onViewAllHistory
        self.onNewTranscription = onNewTranscription
        self.onTranscribeFile = onTranscribeFile
        self.onRecordMeeting = onRecordMeeting
        self.onNewNote = onNewNote
        let stored = Self.isPreview ? false : UserDefaults.standard.bool(forKey: "hasDismissedHotkeyReminder")
        _hasDismissedHotkeyReminder = State(initialValue: stored)
    }

    // MARK: - Computed Stats

    private var totalSessions: Int { transcriptions.count }

    private var totalWords: Int {
        transcriptions.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    private var totalDuration: TimeInterval {
        transcriptions.reduce(0) { $0 + $1.duration }
    }

    private var averageWPM: Double {
        guard totalDuration > 0 else { return 0 }
        let minutes = totalDuration / 60
        return Double(totalWords) / max(minutes, 1)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let record = detailRecord, record.isMediaTranscription {
                MediaTranscriptionDetailView(
                    record: record,
                    folders: folders,
                    onBack: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            detailRecord = nil
                        }
                    },
                    onAssignFolder: { folder in assignRecord(record, to: folder) },
                    onRemoveFromFolder: {
                        if record.folder != nil {
                            removeRecordFromFolder(record)
                        }
                    },
                    onRenameSpeakers: { labelsBySpeakerID in
                        renameSpeakerLabels(for: record, labelsBySpeakerID: labelsBySpeakerID)
                    },
                    onDelete: { pendingDeletionRecord = record }
                )
                .background(AppColors.contentBackground)
            } else {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                            heroSection
                            statsSection

                            if !hasDismissedHotkeyReminder {
                                hotkeyReminderCard
                            }

                            recentActivitySection
                        }
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                        .padding(.top, AppTheme.Window.mainContentTopInset)
                        .padding(.bottom, AppTheme.Spacing.xxl)
                    }
                }
                .background(AppColors.contentBackground)
            }
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
    }

    // MARK: - Detail helpers (mirror HistoryView behavior)

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

    private func confirmDeletePendingRecord() {
        guard let record = pendingDeletionRecord else { return }
        let deletedID = record.id
        pendingDeletionRecord = nil

        do {
            try historyStore.delete(record)
            if detailRecord?.id == deletedID {
                detailRecord = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsNote(record: TranscriptionRecord) {
        let notesStore = NotesStore(modelContext: modelContext)
        Task { @MainActor in
            let titlePrefix = String(record.text.prefix(50))
            let title = titlePrefix.count < record.text.count ? "\(titlePrefix)…" : titlePrefix

            var noteContent = record.text
            if let original = record.originalText, !original.isEmpty, original != record.text {
                noteContent += "\n\n---\n\nOriginal:\n\(original)"
            }
            if let enhancedWith = record.enhancedWith {
                noteContent += "\n\n---\n\nEnhanced with: \(enhancedWith)"
            }
            try? await notesStore.create(title: title, content: noteContent)
        }
    }

    // MARK: - Hero Section

    private var isActive: Bool {
        indicatorState.isRecording || indicatorState.isProcessing
    }

    private enum HeroPhase: Equatable {
        case idle
        case recording
        case processing
        case completed(FloatingIndicatorState.CompletionKind)
    }

    private var heroPhase: HeroPhase {
        if let completion = indicatorState.recentCompletion {
            return .completed(completion)
        }
        if indicatorState.isRecording { return .recording }
        if indicatorState.isProcessing { return .processing }
        return .idle
    }

    private var heroAccentColor: Color {
        switch heroPhase {
        case .recording: return AppColors.recording
        case .processing: return AppColors.processing
        case .completed: return AppColors.success
        case .idle: return AppColors.accent
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomTrailing) {
            // Animated gradient background driven by hero phase
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        heroAccentColor.opacity(heroPhase == .idle ? 0.15 : 0.18),
                        heroAccentColor.opacity(0.06),
                        AppColors.surfaceBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                WaveShape(amplitude: 12, frequency: 2.5, phase: 0)
                    .fill(heroAccentColor.opacity(0.06))
                    .frame(height: 60)
                    .offset(y: 10)

                WaveShape(amplitude: 8, frequency: 3, phase: .pi / 3)
                    .fill(heroAccentColor.opacity(0.04))
                    .frame(height: 50)
                    .offset(y: 20)
            }

            // Content — one concrete view per phase so SwiftUI can transition
            // cleanly between them.
            HStack(alignment: .center, spacing: AppTheme.Spacing.xxl) {
                heroLeading
                Spacer()
                heroTrailing
            }
            .padding(AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(
                    heroPhase == .idle ? AppColors.border : heroAccentColor.opacity(0.4),
                    lineWidth: heroPhase == .idle ? 1 : 1.5
                )
        )
        .animation(AppTheme.Animation.smooth, value: indicatorState.isRecording)
        .animation(AppTheme.Animation.smooth, value: indicatorState.isProcessing)
        .animation(AppTheme.Animation.smooth, value: indicatorState.recentCompletion)
    }

    @ViewBuilder
    private var heroLeading: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            switch heroPhase {
            case .recording:
                Text(localized("Recording", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.recording)
                    .transition(.blurReplace)

                HeroRecordingTimerView(duration: indicatorState.recordingDuration)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .processing:
                Text(localized("Processing", locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.processing)
                    .transition(.blurReplace)

                Text(localized("Transcribing your audio…", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .completed(let kind):
                Text(localized(kind.title, locale: locale))
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.success)
                    .transition(.blurReplace)

                Text(localized("Added to your library.", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .idle:
                Text(greetingText)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .transition(.blurReplace)

                Text(localized("Your activity at a glance", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @ViewBuilder
    private var heroTrailing: some View {
        switch heroPhase {
        case .recording:
            HStack(spacing: AppTheme.Spacing.lg) {
                FloatingIndicatorWaveformView(
                    audioLevel: indicatorState.audioLevel,
                    isRecording: true,
                    style: .heroRecording
                )
                .frame(width: 120, height: 64)

                heroStopButton
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .processing:
            ProgressView()
                .controlSize(.regular)
                .tint(AppColors.processing)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        case .completed(let kind):
            HeroCompletionBadge(kind: kind)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        case .idle:
            if onNewTranscription != nil {
                heroIdleSplitButton
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    // Idle state: split capsule button — primary tap starts dictation, chevron opens dropdown
    private var heroIdleSplitButton: some View {
        HStack(spacing: 0) {
            // Primary action area
            Button {
                onNewTranscription?()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                    }
                    Text(localized("New Transcription", locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.leading, AppTheme.Spacing.lg)
                .padding(.trailing, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .contentShape(Capsule())
            }
            .buttonStyle(SplitButtonHoverStyle())

            // Divider — stretches full capsule height with inset
            Rectangle()
                .fill(AppColors.accent.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, AppTheme.Spacing.sm)

            // Chevron button — no system menu chrome, fills right side
            Button {
                withAnimation(AppTheme.Animation.fast) {
                    showingActionMenu.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .rotationEffect(.degrees(showingActionMenu ? 180 : 0))
                    .animation(AppTheme.Animation.fast, value: showingActionMenu)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChevronButtonHoverStyle())
            .frame(width: 44)
            .popover(isPresented: $showingActionMenu, arrowEdge: .bottom) {
                actionMenuContent
            }
        }
        .background(
            Capsule()
                .fill(AppColors.accent.opacity(0.1))
        )
        .overlay(
            Capsule()
                .strokeBorder(AppColors.accent.opacity(0.25), lineWidth: 1)
        )
    }

    // Custom dropdown content for the action menu popover
    private var actionMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionMenuItem(
                icon: "waveform",
                iconColor: AppColors.accent,
                title: localized("New Transcription", locale: locale),
                subtitle: localized("Start voice dictation", locale: locale)
            ) {
                showingActionMenu = false
                onNewTranscription?()
            }

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.Spacing.sm)

            actionMenuItem(
                icon: "person.2.fill",
                iconColor: AppColors.success,
                title: localized("Record Meeting", locale: locale),
                subtitle: localized("Capture system & mic audio", locale: locale)
            ) {
                showingActionMenu = false
                onRecordMeeting?()
            }

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.Spacing.sm)

            actionMenuItem(
                icon: "doc.text.fill",
                iconColor: AppColors.processing,
                title: localized("Transcribe a File", locale: locale),
                subtitle: localized("Import audio or video files", locale: locale)
            ) {
                showingActionMenu = false
                onTranscribeFile?()
            }

            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
                .padding(.horizontal, AppTheme.Spacing.sm)

            actionMenuItem(
                icon: "note.text.badge.plus",
                iconColor: AppColors.accent,
                title: localized("New Note", locale: locale),
                subtitle: settingsStore.assignment(for: .transcriptionEnhancement) != nil
                    ? localized("Dictate and enhance into a note", locale: locale)
                    : localized("Requires AI Enhancement (Settings › AI)", locale: locale),
                isDisabled: settingsStore.assignment(for: .transcriptionEnhancement) == nil
            ) {
                showingActionMenu = false
                onNewNote?()
            }
        }
        .padding(AppTheme.Spacing.xs)
        .frame(width: 260)
    }

    private func actionMenuItem(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(ActionMenuItemStyle())
        .disabled(isDisabled)
        .help(isDisabled ? localized("Enable AI Enhancement in Settings to record notes.", locale: locale) : "")
    }

    // Recording state: pulsing stop button
    private var heroStopButton: some View {
        Button {
            onNewTranscription?()
        } label: {
            ZStack {
                // Pulsing outer ring
                Circle()
                    .fill(AppColors.recording.opacity(0.08))
                    .frame(width: 56, height: 56)
                    .modifier(PulsingRingModifier())

                // Solid ring
                Circle()
                    .fill(AppColors.recording.opacity(0.15))
                    .frame(width: 48, height: 48)

                // Stop icon
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppColors.recording)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: AppTheme.Spacing.lg) {
            StatCard(
                icon: "mic.fill",
                iconColor: AppColors.accent,
                title: localized("Total Recordings", locale: locale),
                value: "\(totalSessions)",
                trendIcon: "arrow.up.right"
            )

            StatCard(
                icon: "text.word.spacing",
                iconColor: AppColors.processing,
                title: localized("Words Transcribed", locale: locale),
                value: formatNumber(totalWords),
                trendIcon: "arrow.up.right"
            )

            StatCard(
                icon: "clock.fill",
                iconColor: AppColors.success,
                title: localized("Time Saved", locale: locale),
                value: formatTimeSaved(totalWords),
                trendIcon: "arrow.up.right"
            )

            StatCard(
                icon: "gauge.with.needle",
                iconColor: AppColors.accent,
                title: localized("Avg Speed", locale: locale),
                value: String(format: "%.0f", averageWPM),
                trendIcon: "arrow.up.right"
            )
        }
    }

    // MARK: - Hotkey Reminder Card

    private var hotkeyReminderCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top) {
                HStack(spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        KeyCapView(text: "⌥")
                        Text("+")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                        KeyCapView(text: "Space")
                    }

                    Text(localized("to dictate and let Pindrop transcribe for you", locale: locale))
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                Button {
                    hasDismissedHotkeyReminder = true
                    if !Self.isPreview {
                        UserDefaults.standard.set(true, forKey: "hasDismissedHotkeyReminder")
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(localized("Dismiss", locale: locale))
            }

            Text(localized("Press and hold to dictate in any app. Pindrop will transcribe your speech and insert the text where your cursor is.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)

            Button {
                onOpenHotkeys?()
            } label: {
                Text(localized("Customize hotkey", locale: locale))
                    .font(AppTypography.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.textPrimary)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.xl)
        .highlightedCardStyle()
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Text(localized("Recent Activity", locale: locale))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if !transcriptions.isEmpty {
                    Button(localized("View All", locale: locale)) {
                        onViewAllHistory?()
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                    .buttonStyle(.plain)
                }
            }

            if transcriptions.isEmpty {
                emptyActivityView
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(transcriptions.prefix(5))) { record in
                        TranscriptionHistoryRow(
                            record: record,
                            isSelected: selectedTranscriptionID == record.persistentModelID,
                            timestampStyle: .relative,
                            onTap: {
                                if record.isMediaTranscription {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        detailRecord = record
                                    }
                                } else {
                                    withAnimation(AppTheme.Animation.fast) {
                                        if selectedTranscriptionID == record.persistentModelID {
                                            selectedTranscriptionID = nil
                                        } else {
                                            selectedTranscriptionID = record.persistentModelID
                                        }
                                    }
                                }
                            },
                            onSaveAsNote: { saveAsNote(record: record) }
                        )
                    }
                }
            }
        }
    }

    private var emptyActivityView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textTertiary)

            Text(localized("No activity yet", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Start a recording or transcribe a file to see your activity here", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxxl)
        .cardStyle()
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return localized("Good morning", locale: locale)
        case 12..<17: return localized("Good afternoon", locale: locale)
        case 17..<22: return localized("Good evening", locale: locale)
        default: return localized("Good night", locale: locale)
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }

    private func formatTimeSaved(_ words: Int) -> String {
        let typingMinutes = Double(words) / 40
        let speakingMinutes = Double(words) / 150
        let savedMinutes = typingMinutes - speakingMinutes

        if savedMinutes < 60 {
            return String(format: "%.0f min", max(savedMinutes, 0))
        } else {
            let hours = savedMinutes / 60
            return String(format: "%.1f hrs", hours)
        }
    }
}

// MARK: - Wave Shape

private struct WaveShape: Shape {
    let amplitude: CGFloat
    let frequency: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))

        for x in stride(from: 0, through: rect.width, by: 1) {
            let relativeX = x / rect.width
            let y = amplitude * sin(2 * .pi * frequency * relativeX + phase) + rect.height / 2
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Hero Recording Helpers

private struct HeroCompletionBadge: View {
    let kind: FloatingIndicatorState.CompletionKind

    @State private var appeared = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.success.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.success)
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
            }

            Image(systemName: kind.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.success)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.success.opacity(0.12))
                )
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                appeared = true
            }
        }
    }
}

private struct HeroRecordingTimerView: View {
    let duration: TimeInterval

    private var minutes: Int { Int(duration) / 60 }
    private var seconds: Int { Int(duration) % 60 }
    private var tenths: Int { Int((duration - floor(duration)) * 10) }

    var body: some View {
        Text("\(minutes):\(String(format: "%02d", seconds)).\(tenths)")
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundStyle(AppColors.recording.opacity(0.8))
            .contentTransition(.numericText())
            .animation(AppTheme.Animation.fast, value: duration)
    }
}

private struct PulsingRingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.25 : 1.0)
            .opacity(isPulsing ? 0 : 0.5)
            .animation(
                .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

/// Subtle hover effect for the primary area of the split button.
/// Brightens the background without adding a visible button chrome.
private struct SplitButtonHoverStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppTheme.Radius.full,
                    bottomLeadingRadius: AppTheme.Radius.full,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(AppColors.accent.opacity(isHovered || configuration.isPressed ? 0.08 : 0))
            )
            .onHover { hovering in
                withAnimation(AppTheme.Animation.fast) {
                    isHovered = hovering
                }
            }
    }
}

private struct ChevronButtonHoverStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: AppTheme.Radius.full,
                    topTrailingRadius: AppTheme.Radius.full
                )
                .fill(AppColors.accent.opacity(isHovered || configuration.isPressed ? 0.08 : 0))
            )
            .onHover { hovering in
                withAnimation(AppTheme.Animation.fast) {
                    isHovered = hovering
                }
            }
    }
}

private struct ActionMenuItemStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(isHovered || configuration.isPressed
                          ? AppColors.accent.opacity(0.08)
                          : Color.clear)
            )
            .onHover { hovering in
                withAnimation(AppTheme.Animation.fast) {
                    isHovered = hovering
                }
            }
    }
}

extension FloatingIndicatorWaveformStyle {
    /// Hero section waveform — fills available width, tall enough to match stop button
    static let heroRecording = FloatingIndicatorWaveformStyle(
        layout: .dynamic(minimumCount: 24, edgeAttenuation: 0.25),
        barWidth: 3,
        barSpacing: 2.5,
        minimumHeight: 4,
        maximumHeight: 56,
        idleHeight: 6,
        color: AppColors.recording,
        animationInterval: 0.05
    )
}

// MARK: - Subviews

struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.mono)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppColors.surfaceBackground)
            )
            .hairlineBorder(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm),
                style: AppColors.border
            )
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var trendIcon: String? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)

                Spacer()

                if let trendIcon {
                    Image(systemName: trendIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.success.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(value)
                    .font(AppTypography.statMedium)
                    .foregroundStyle(AppColors.textPrimary)

                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: isHovered ? AppColors.border.opacity(0.9) : AppColors.border
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.05) : .clear,
            radius: isHovered ? 10 : 0,
            y: isHovered ? 4 : 0
        )
        .animation(AppTheme.Animation.fast, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}

// Keep this accessible for HistoryView which also uses it
struct RecentTranscriptionRow: View {
    let record: TranscriptionRecord

    @State private var isHovered = false

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: record.timestamp, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(timeAgo)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 60, alignment: .leading)

            Rectangle()
                .fill(AppColors.accent)
                .frame(width: 3)
                .clipShape(Capsule())

            Text(record.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(text: record.text)
                .opacity(isHovered ? 0.85 : 0.65)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: isHovered ? AppColors.border.opacity(0.9) : AppColors.border
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.05) : .clear,
            radius: isHovered ? 10 : 0,
            y: isHovered ? 4 : 0
        )
        .animation(AppTheme.Animation.fast, value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }
}

#Preview("Dashboard - With Data") {
    DashboardView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Empty") {
    DashboardView()
        .modelContainer(PreviewContainer.empty)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Dark") {
    DashboardView()
        .modelContainer(PreviewContainer.withSampleData)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.dark)
}
