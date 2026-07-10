//
//  LibraryRowChrome.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Collapsed library row chrome with fixed lanes (spec §5):
/// 64 pt time · 16 pt icon · flexible preview · destination · 74 pt play chip.
struct LibraryRowChrome<Icon: View, Play: View>: View {
    let timeText: String
    let preview: String
    var destination: String? = nil
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var playChip: () -> Play
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                Text(timeText)
                    .font(AppTypography.monoTime)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 64, alignment: .leading)
                    .monospacedDigit()

                icon()
                    .frame(width: 16, height: 16)

                Text(preview)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let destination, !destination.isEmpty {
                    Text(destination)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                playChip()
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }
}

#Preview("LibraryRowChrome") {
    VStack(spacing: 0) {
        LibraryRowChrome(
            timeText: "2:14 PM",
            preview: "Draft the launch notes for Scorched Earth…",
            destination: "→ Slack"
        ) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        } playChip: {
            PlayChip(durationText: "0:31", action: {})
        }

        LibraryRowChrome(
            timeText: "9:02 AM",
            preview: "Weekly planning with design and eng",
            destination: nil
        ) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        } playChip: {
            PlayChip(durationText: "0:24", isExpired: true)
        }
    }
    .background(AppColors.contentBackground)
    .themeRefresh()
}
