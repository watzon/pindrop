//
//  PlayChip.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

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
            HStack(spacing: 5) {
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
            .frame(width: 74)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
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
