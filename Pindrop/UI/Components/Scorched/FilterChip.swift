//
//  FilterChip.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Pill filter chip (spec §4). Selected: ink bg / page text. Unselected: line border / ink-2.
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.label)
            }
            .foregroundStyle(isSelected ? AppColors.contentBackground : AppColors.textSecondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppColors.textPrimary : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("FilterChip") {
    HStack(spacing: 6) {
        FilterChip(title: "All", isSelected: true, action: {})
        FilterChip(title: "Dictations", isSelected: false, action: {})
        FilterChip(title: "Meetings", isSelected: false, action: {})
        FilterChip(title: "Newest", systemImage: "arrow.up.arrow.down", isSelected: false, action: {})
    }
    .padding()
    .background(AppColors.contentBackground)
    .themeRefresh()
}
