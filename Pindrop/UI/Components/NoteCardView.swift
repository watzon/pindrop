//
//  NoteCardView.swift
//  Pindrop
//
//  Created on 2026-01-29.
//

import SwiftUI
import SwiftData

struct NoteCardView: View {
    let note: NoteSchema.Note
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(note.title.isEmpty ? "Untitled Note" : note.title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack(alignment: .bottom) {
                Text(note.content.isEmpty ? "No content" : note.content)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                LinearGradient(
                    colors: [
                        (isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground).opacity(0),
                        (isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
            .clipped()
            
            HStack(spacing: AppTheme.Spacing.sm) {
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(AppTypography.tiny)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        if note.tags.count > 3 {
                            Text("+\(note.tags.count - 3)")
                                .font(AppTypography.tiny)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                Text(relativeDateString)
                    .font(AppTypography.tiny)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1.0, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .fill(isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(
                    isSelected ? AppColors.accent : AppColors.border.opacity(0.5),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: isHovered ? Color.black.opacity(0.08) : Color.clear,
            radius: 8,
            x: 0,
            y: 2
        )
        .onHover { hovering in
            withAnimation(AppTheme.Animation.fast) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Divider()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var relativeDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.updatedAt, relativeTo: Date())
    }
}

#Preview("Note Card - Default") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: NoteSchema.Note.self, configurations: config)
    let note = NoteSchema.Note(
        title: "Project Ideas",
        content: "1. AI Dictation\n2. Native Mac App\n3. Open Source\nThis is a longer preview to test truncation and layout.",
        tags: ["ideas", "dev", "swift"],
        isPinned: true
    )
    
    return NoteCardView(
        note: note,
        isSelected: false,
        onOpen: {},
        onDelete: {}
    )
    .padding()
    .frame(width: 250, height: 250)
    .modelContainer(container)
}

#Preview("Note Card - Selected") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: NoteSchema.Note.self, configurations: config)
    let note = NoteSchema.Note(
        title: "Meeting Notes",
        content: "Discussed Q1 roadmap and design system updates.",
        tags: ["work", "meeting"],
        isPinned: false
    )
    
    return NoteCardView(
        note: note,
        isSelected: true,
        onOpen: {},
        onDelete: {}
    )
    .padding()
    .frame(width: 250, height: 250)
    .modelContainer(container)
}
