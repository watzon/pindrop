//
//  DashboardView.swift
//  Pindrop
//
//  Dashboard home view with stats, quick actions, and hotkey reminder
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @State private var hasDismissedHotkeyReminder: Bool
    
    var onOpenHotkeys: (() -> Void)?
    var onViewAllHistory: (() -> Void)?
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    init(onOpenHotkeys: (() -> Void)? = nil, onViewAllHistory: (() -> Void)? = nil) {
        self.onOpenHotkeys = onOpenHotkeys
        self.onViewAllHistory = onViewAllHistory
        let stored = Self.isPreview ? false : UserDefaults.standard.bool(forKey: "hasDismissedHotkeyReminder")
        _hasDismissedHotkeyReminder = State(initialValue: stored)
    }
    
    private var totalSessions: Int {
        transcriptions.count
    }
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.bottom, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Window.mainContentTopInset)
                .background(AppColors.contentBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    recentSection
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .background(AppColors.contentBackground)
        }
        .background(AppColors.contentBackground)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            welcomeHeader

            if !hasDismissedHotkeyReminder {
                hotkeyReminderCard
            }

            statsSection
        }
    }
    
    // MARK: - Welcome Header
    
    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(greetingText)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(localized("Ready to transcribe", locale: locale))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            // Quick stats badges
            HStack(spacing: AppTheme.Spacing.lg) {
                statBadge(icon: "waveform", value: "\(totalSessions)", label: localized("sessions", locale: locale))
                statBadge(icon: "text.word.spacing", value: formatNumber(totalWords), label: localized("words", locale: locale))
                statBadge(icon: "gauge.with.needle", value: String(format: "%.0f", averageWPM), label: localized("WPM", locale: locale))
            }
        }
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return localized("Good morning", locale: locale)
        case 12..<17: return localized("Good afternoon", locale: locale)
        case 17..<22: return localized("Good evening", locale: locale)
        default: return localized("Good night", locale: locale)
        }
    }
    
    private func statBadge(icon: String, value: String, label: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }
    
    // MARK: - Hotkey Reminder Card
    
    private var hotkeyReminderCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header with close button
            HStack(alignment: .top) {
                // Main instruction
                HStack(spacing: AppTheme.Spacing.md) {
                    // Hotkey display
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
                
                // Close button
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
            
            // Description
            Text(localized("Press and hold to dictate in any app. Pindrop will transcribe your speech and insert the text where your cursor is.", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
            
            // Action button
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
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(localized("Your Stats", locale: locale))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppTheme.Spacing.lg) {
                StatCard(
                    icon: "mic.fill",
                    iconColor: AppColors.recording,
                    title: localized("Sessions", locale: locale),
                    value: "\(totalSessions)",
                    subtitle: localized("recordings", locale: locale)
                )
                
                StatCard(
                    icon: "text.word.spacing",
                    iconColor: AppColors.accent,
                    title: localized("Words", locale: locale),
                    value: formatNumber(totalWords),
                    subtitle: localized("transcribed", locale: locale)
                )
                
                StatCard(
                    icon: "clock.fill",
                    iconColor: AppColors.processing,
                    title: localized("Time Saved", locale: locale),
                    value: formatTimeSaved(totalWords),
                    subtitle: localized("vs typing", locale: locale)
                )
                
                StatCard(
                    icon: "gauge.with.needle",
                    iconColor: .green,
                    title: localized("Avg Speed", locale: locale),
                    value: String(format: "%.0f", averageWPM),
                    subtitle: localized("words/min", locale: locale)
                )
            }
        }
    }
    
    // MARK: - Recent Section
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Text(localized("Recent Transcriptions", locale: locale))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !transcriptions.isEmpty {
                    Button(localized("View all", locale: locale)) {
                        onViewAllHistory?()
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                    .buttonStyle(.plain)
                }
            }
            
            if transcriptions.isEmpty {
                emptyRecentView
            } else {
                recentTranscriptionsList
            }
        }
    }
    
    private var emptyRecentView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(localized("No transcriptions yet", locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            
            Text(localized("Use the hotkey to start your first recording", locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxxl)
        .cardStyle()
    }
    
    private var recentTranscriptionsList: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(Array(transcriptions.prefix(5))) { record in
                HistoryTranscriptionRow(record: record)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }
    
    private func formatTimeSaved(_ words: Int) -> String {
        // Assuming average typing speed of 40 WPM vs speaking at ~150 WPM
        let typingMinutes = Double(words) / 40
        let speakingMinutes = Double(words) / 150
        let savedMinutes = typingMinutes - speakingMinutes
        
        if savedMinutes < 60 {
            return String(format: "%.0f min", savedMinutes)
        } else {
            let hours = savedMinutes / 60
            return String(format: "%.1f hrs", hours)
        }
    }
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
    let subtitle: String

    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(value)
                    .font(AppTypography.statMedium)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
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
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

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
            // Time
            Text(timeAgo)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 60, alignment: .leading)
            
            // Vertical bar
            Rectangle()
                .fill(AppColors.accent)
                .frame(width: 3)
                .clipShape(Capsule())
            
            // Content
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
        .onHover { hovering in
            isHovered = hovering
        }
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
