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
    let onTogglePin: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                Text(note.title.isEmpty ? "Untitled Note" : note.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer(minLength: 0)
                
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.accent)
                }
            }
            
            Text(note.content.isEmpty ? "No content" : note.content)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(note.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(AppTypography.tiny)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.surfaceBackground.opacity(0.5))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(AppColors.border.opacity(0.5), lineWidth: 0.5))
                            }
                        }
                    }
                }
                
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
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
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
            Button(action: onTogglePin) {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        if isSelected {
            return AppColors.accentBackground
        }
        return isHovered ? AppColors.elevatedSurface : AppColors.surfaceBackground
    }
    
    private var borderColor: Color {
        if isSelected {
            return AppColors.accent
        }
        if isHovered {
            return AppColors.textTertiary.opacity(0.3)
        }
        return AppColors.border
    }
    
    private var relativeDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: note.createdAt, relativeTo: Date())
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
        onDelete: {},
        onTogglePin: {}
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
        onDelete: {},
        onTogglePin: {}
    )
    .padding()
    .frame(width: 250, height: 250)
    .modelContainer(container)
}
