//
//  PlayChip.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Load-bearing play-chip metrics (spec §5).
/// Total rendered width must stay `width` — padding is applied *before* the outer frame.
enum PlayChipMetrics {
    static let width: CGFloat = 74
    static let verticalPadding: CGFloat = 3
    static let horizontalPadding: CGFloat = 9
    static let iconTextGap: CGFloat = 5
}

/// Fixed 74 pt play duration chip (spec §5). Expired variant strikes through duration and hides play glyph.
struct PlayChip: View {
    let durationText: String
    var isExpired: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            if !isExpired {
                action?()
            }
        } label: {
            // Order is load-bearing: content → padding → frame(width) → background.
            // Framing before padding would push padding outside the 74 pt lane (→ 92 pt).
            HStack(spacing: PlayChipMetrics.iconTextGap) {
                if !isExpired {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                Text(durationText)
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .strikethrough(isExpired, color: AppColors.textSecondary)
            }
            .padding(.vertical, PlayChipMetrics.verticalPadding)
            .padding(.horizontal, PlayChipMetrics.horizontalPadding)
            .frame(width: PlayChipMetrics.width)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExpired || action == nil)
        .opacity(isExpired ? 0.85 : 1)
    }
}

#Preview("PlayChip") {
    HStack(spacing: 12) {
        PlayChip(durationText: "0:31", action: {})
        PlayChip(durationText: "2:14", isExpired: true)
    }
    .padding()
    .background(AppColors.contentBackground)
    .themeRefresh()
}
