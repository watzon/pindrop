//
//  TranscriptionHistoryRow.swift
//  Pindrop
//
//  Shared row component used by the Dashboard "Recent Activity" list and
//  HistoryView. Driven by callbacks so each caller decides what happens on
//  tap — Dashboard navigates to history; History expands in place (voice)
//  or pushes into the media detail view.
//

import SwiftUI
import SwiftData

struct TranscriptionHistoryRow: View {
    enum TimestampStyle {
        case relative   // "5m ago" — used on Dashboard
        case absolute   // "3:42 PM" — used in History's date-grouped list
    }

    let record: TranscriptionRecord
    var isSelected: Bool = false
    var timestampStyle: TimestampStyle = .relative
    var onTap: () -> Void = {}
    var onSaveAsNote: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showingSaveSuccess = false
    @Namespace private var enhancedNamespace

    private var isEnhanced: Bool { record.enhancedWith != nil }

    // MARK: Derived

    private var sourceKind: MediaSourceKind { record.resolvedSourceKind }

    private var typeInfo: (icon: String, color: Color, label: String) {
        switch sourceKind {
        case .voiceRecording:
            return ("mic.fill", AppColors.accent, "Voice")
        case .manualCapture:
            return ("person.2.fill", AppColors.success, "Meeting")
        case .importedFile:
            return ("headphones", AppColors.processing, "Audio")
        case .webLink:
            return ("film", AppColors.processing, "Video")
        }
    }

    private var displayTitle: String {
        if let preferredTitle = record.preferredTitle, !preferredTitle.isEmpty {
            return preferredTitle
        }
        let text = record.text
        if text.count > 80 {
            return String(text.prefix(80)) + "…"
        }
        return text
    }

    // Metadata string *without* the Enhanced tag — Enhanced is rendered as a
    // separate view so we can matched-geometry animate it into the expanded
    // section.
    private var metadataText: String {
        var parts: [String] = []
        parts.append(typeInfo.label)

        if record.duration > 0 {
            let minutes = Int(record.duration) / 60
            let seconds = Int(record.duration) % 60
            if minutes > 0 {
                parts.append("\(minutes) min")
            } else {
                parts.append("\(seconds) sec")
            }
        }

        let wordCount = record.text.split(separator: " ").count
        if wordCount > 0 {
            parts.append("\(formatWordCount(wordCount)) words")
        }

        return parts.joined(separator: " · ")
    }

    private static let absoluteTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private var timestampLabel: String {
        switch timestampStyle {
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: record.timestamp, relativeTo: Date())
        case .absolute:
            return Self.absoluteTimeFormatter.string(from: record.timestamp)
        }
    }

    private var hasOriginalText: Bool {
        guard let original = record.originalText else { return false }
        return !original.isEmpty && original != record.text
    }

    private var cardBackground: Color {
        if isSelected { return AppColors.accentBackground }
        if isHovered { return AppColors.elevatedSurface }
        return AppColors.surfaceBackground
    }

    private var cardBorder: Color {
        if isSelected { return AppColors.accent.opacity(0.3) }
        if isHovered { return AppColors.border.opacity(0.9) }
        return AppColors.border
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            headerRow

            if isSelected {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(cardBackground)
        )
        .hairlineStroke(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous),
            style: cardBorder
        )
        .animation(AppTheme.Animation.fast, value: isHovered)
        .animation(AppTheme.Animation.fast, value: isSelected)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onTap() }
        .contextMenu { contextMenuItems }
        .overlay(alignment: .bottom) {
            if showingSaveSuccess {
                Text("Saved to Notes")
                    .font(AppTypography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(Capsule(style: .continuous).fill(AppColors.accent))
                    .transition(.opacity.combined(with: .scale))
                    .padding(.bottom, AppTheme.Spacing.xs)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Type icon chip
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(typeInfo.color.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: typeInfo.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(typeInfo.color)
            }

            // Title + metadata
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(displayTitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(metadataText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)

                    if isEnhanced, !isSelected {
                        Text("· ")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        enhancedBadge(style: .inline)
                    }
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            // Time + type pill
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxs) {
                Text(timestampLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                Text(typeInfo.label)
                    .font(AppTypography.tiny)
                    .foregroundStyle(typeInfo.color)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(typeInfo.color.opacity(0.1))
                    )
            }

            CopyButton(text: record.text, size: 11)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        Rectangle()
            .fill(AppColors.divider)
            .frame(height: 1)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if isEnhanced {
                enhancedBadge(style: .title)
            }

            Text(record.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }

        if hasOriginalText {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Rectangle()
                    .fill(AppColors.divider)
                    .frame(height: 1)

                Text("Original")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)

                Text(record.originalText ?? "")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private enum EnhancedBadgeStyle {
        case inline   // sits on the metadata line when collapsed
        case title    // sits above the transcript when expanded, matching "Original"
    }

    @ViewBuilder
    private func enhancedBadge(style: EnhancedBadgeStyle) -> some View {
        Text("Enhanced")
            .font(style == .inline ? AppTypography.caption : AppTypography.tiny)
            .foregroundStyle(style == .inline ? AppColors.textTertiary : AppColors.accent)
            .matchedGeometryEffect(id: "enhanced-label", in: enhancedNamespace)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.text, forType: .string)
        } label: {
            Label("Copy Transcript", systemImage: "doc.on.doc")
        }

        if hasOriginalText {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.originalText ?? "", forType: .string)
            } label: {
                Label("Copy Original", systemImage: "doc.on.doc.fill")
            }
        }

        if let onSaveAsNote {
            Divider()

            Button {
                onSaveAsNote()
                flashSaveSuccess()
            } label: {
                Label("Save as Note", systemImage: "note.text.badge.plus")
            }
        }
    }

    private func flashSaveSuccess() {
        withAnimation(AppTheme.Animation.fast) {
            showingSaveSuccess = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(AppTheme.Animation.fast) {
                showingSaveSuccess = false
            }
        }
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}
