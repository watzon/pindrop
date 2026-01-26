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
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var transcriptions: [TranscriptionRecord]
    @AppStorage("hasDismissedHotkeyReminder") private var hasDismissedHotkeyReminder = false

    var onOpenSettings: (() -> Void)?
    
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
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                // Welcome header
                welcomeHeader
                
                // Hotkey reminder card (only shown if not dismissed)
                if !hasDismissedHotkeyReminder {
                    hotkeyReminderCard
                }
                
                // Stats grid
                statsSection
                
                // Recent transcriptions
                recentSection
            }
            .padding(AppTheme.Spacing.xxl)
        }
        .background(AppColors.contentBackground)
    }
    
    // MARK: - Welcome Header
    
    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(greetingText)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Ready to transcribe")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            // Quick stats badges
            HStack(spacing: AppTheme.Spacing.lg) {
                statBadge(icon: "waveform", value: "\(totalSessions)", label: "sessions")
                statBadge(icon: "text.word.spacing", value: formatNumber(totalWords), label: "words")
                statBadge(icon: "gauge.with.needle", value: String(format: "%.0f", averageWPM), label: "WPM")
            }
        }
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
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
                    
                    Text("to dictate and let Pindrop transcribe for you")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                // Close button
                Button {
                    hasDismissedHotkeyReminder = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            
            // Description
            Text("Press and hold to dictate in any app. Pindrop will transcribe your speech and insert the text where your cursor is.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
            
            // Action button
            Button {
                onOpenSettings?()
            } label: {
                Text("Customize hotkey")
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
            Text("Your Stats")
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
                    title: "Sessions",
                    value: "\(totalSessions)",
                    subtitle: "recordings"
                )
                
                StatCard(
                    icon: "text.word.spacing",
                    iconColor: AppColors.accent,
                    title: "Words",
                    value: formatNumber(totalWords),
                    subtitle: "transcribed"
                )
                
                StatCard(
                    icon: "clock.fill",
                    iconColor: AppColors.processing,
                    title: "Time Saved",
                    value: formatTimeSaved(totalWords),
                    subtitle: "vs typing"
                )
                
                StatCard(
                    icon: "gauge.with.needle",
                    iconColor: .green,
                    title: "Avg Speed",
                    value: String(format: "%.0f", averageWPM),
                    subtitle: "words/min"
                )
            }
        }
    }
    
    // MARK: - Recent Section
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Text("Recent Transcriptions")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !transcriptions.isEmpty {
                    Button("View all") {
                        // Navigation to history will be handled by parent
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
            
            Text("No transcriptions yet")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            
            Text("Use the hotkey to start your first recording")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxxl)
        .cardStyle()
    }
    
    private var recentTranscriptionsList: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(Array(transcriptions.prefix(3))) { record in
                RecentTranscriptionRow(record: record)
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
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
    }
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    
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
        .cardStyle()
    }
}

struct RecentTranscriptionRow: View {
    let record: TranscriptionRecord
    
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
        }
        .padding(AppTheme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Dashboard - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    let context = container.mainContext
    
    // Add sample data
    for i in 0..<10 {
        let record = TranscriptionRecord(
            text: "This is sample transcription number \(i + 1). It contains some text to demonstrate the dashboard.",
            timestamp: Date().addingTimeInterval(Double(-i * 3600)),
            duration: Double.random(in: 5...60),
            modelUsed: "base.en"
        )
        context.insert(record)
    }
    
    return DashboardView()
        .modelContainer(container)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    
    return DashboardView()
        .modelContainer(container)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dashboard - Dark") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TranscriptionRecord.self, configurations: config)
    let context = container.mainContext
    
    for i in 0..<5 {
        let record = TranscriptionRecord(
            text: "Sample transcription \(i + 1)",
            timestamp: Date().addingTimeInterval(Double(-i * 3600)),
            duration: Double.random(in: 5...30),
            modelUsed: "tiny.en"
        )
        context.insert(record)
    }
    
    return DashboardView()
        .modelContainer(container)
        .frame(width: 800, height: 700)
        .preferredColorScheme(.dark)
}
