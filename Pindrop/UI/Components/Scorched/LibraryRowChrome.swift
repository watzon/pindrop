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
    /// Optional second line under the preview (meeting meta: "3 speakers · diarized…").
    var previewMeta: String? = nil
    var destination: String? = nil
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var playChip: () -> Play
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let previewMeta, !previewMeta.isEmpty {
                        Text(previewMeta)
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let destination, !destination.isEmpty {
                    Text(destination)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                }
                // Padding INSIDE the button label so the whole row — including its
                // breathing room — is clickable, not just the text lanes.
                .padding(.vertical, 13)
                .padding(.leading, 24)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .keyboardFocusRing(RoundedRectangle(cornerRadius: 6, style: .continuous))

            playChip()
                .frame(width: PlayChipMetrics.width, alignment: .trailing)
                .padding(.trailing, 24)
        }
        // Divider inset to the content column (matches the section rules).
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
                .padding(.horizontal, 24)
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
