//
//  NoteHistoryRow.swift
//  Pindrop
//
//  Sibling of TranscriptionHistoryRow for rendering NoteSchema.Note entries
//  in the unified History list. Matches the visual rhythm of the transcription
//  row (icon chip | title + meta | time + type pill) with note-appropriate
//  content and actions.
//

import SwiftUI

struct NoteHistoryRow: View {
    let note: NoteSchema.Note
    var onTap: () -> Void = {}
    var onDelete: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil

    @State private var isHovered = false

    private static let absoluteTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private var timestampLabel: String {
        Self.absoluteTimeFormatter.string(from: note.updatedAt)
    }

    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let preview = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > 80 { return String(preview.prefix(80)) + "…" }
        return preview.isEmpty ? "Untitled Note" : preview
    }

    private var metadataText: String {
        var parts: [String] = ["Note"]
        let wordCount = note.content.split(separator: " ").count
        if wordCount > 0 {
            parts.append("\(formatWordCount(wordCount)) words")
        }
        if !note.tags.isEmpty {
            let tagPreview = note.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
            parts.append(tagPreview)
        }
        return parts.joined(separator: " · ")
    }

    private var cardBackground: Color {
        isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground
    }

    private var cardBorder: Color {
        isHovered ? AppColors.border.opacity(0.9) : AppColors.border
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Icon chip — purple-ish note tone
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppColors.accent.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: note.isPinned ? "pin.fill" : "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }

            // Title + metadata
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(displayTitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(metadataText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            // Time + type pill
            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxs) {
                Text(timestampLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                Text("Note")
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(AppColors.accent.opacity(0.1))
                    )
            }

            CopyButton(text: note.content, size: 11)
                .opacity(isHovered ? 1 : 0)
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
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onTap() }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Open Note", systemImage: "square.and.pencil")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.content, forType: .string)
            } label: {
                Label("Copy Content", systemImage: "doc.on.doc")
            }

            if let onTogglePin {
                Button(action: onTogglePin) {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
            }

            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Note", systemImage: "trash")
                }
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
