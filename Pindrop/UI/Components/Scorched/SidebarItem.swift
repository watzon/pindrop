//
//  SidebarItem.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Scorched Earth sidebar nav item (spec §3).
/// Selected: page bg + 1 pt line border, ink label 600, accent icon.
/// Unselected: transparent, ink-2 label 500, ink-2 icon.
struct SidebarItem: View {
    let title: String
    let systemImage: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(isSelected ? AppTypography.labelStrongSelected : AppTypography.labelStrong)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let count {
                    Text("\(count)")
                        .font(AppTypography.monoSmall)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppColors.contentBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? AppColors.border : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview("SidebarItem") {
    VStack(alignment: .leading, spacing: 2) {
        SidebarItem(title: "Home", systemImage: "house", isSelected: false, action: {})
        SidebarItem(title: "Library", systemImage: "books.vertical", count: 128, isSelected: true, action: {})
        SidebarItem(title: "Notes", systemImage: "note.text", count: 12, isSelected: false, action: {})
    }
    .padding(16)
    .frame(width: 236)
    .background(AppColors.windowBackground)
    .themeRefresh()
}
