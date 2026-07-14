//
//  PlayerCardChrome.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import SwiftUI

/// Expanded library player card chrome (spec §6): ground bg, line border, radius 14.
/// Pass `EmptyView` for `player` when the row has no playable audio.
struct PlayerCardChrome<Meta: View, Player: View, Actions: View>: View {
    let transcript: String
    var showsPlayer: Bool = true
    @ViewBuilder var meta: () -> Meta
    @ViewBuilder var player: () -> Player
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            meta()

            Text(transcript)
                .font(AppTypography.transcriptBody)
                .lineSpacing(AppTypography.transcriptBodyLineSpacing)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if showsPlayer {
                player()
            }

            actions()
                .padding(.top, 2)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.windowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: 1)
        )
    }
}

#Preview("PlayerCardChrome") {
    PlayerCardChrome(
        transcript: "Draft the launch notes for Scorched Earth and share them with the team before Friday."
    ) {
        HStack(spacing: 10) {
            Text("2:14 PM")
                .font(AppTypography.monoTime)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 64, alignment: .leading)
            KindBadge(title: "Dictation")
            Text("inserted into Cursor")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text("audio kept 7 days")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(height: 20)
    } player: {
        HStack(spacing: 16) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.contentBackground)
                        .offset(x: 1)
                }
            WaveformView(
                peaks: (0..<40).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) * 0.4))) },
                progress: 0.4,
                onSeek: { _ in }
            )
            Text("0:12 / 0:31")
                .font(AppTypography.monoTime)
                .foregroundStyle(AppColors.textSecondary)
            Text("1.5×")
                .font(AppTypography.monoSmall)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .overlay(
                    Capsule().strokeBorder(AppColors.border, lineWidth: 1)
                )
        }
        .frame(height: 44)
    } actions: {
        HStack(spacing: 8) {
            SecondaryButton(title: "Copy", systemImage: "doc.on.doc", action: {})
            SecondaryButton(title: "Export", systemImage: "square.and.arrow.up", action: {})
            Spacer()
            DestructiveGhostButton(title: "Delete", action: {})
        }
    }
    .padding(24)
    .background(AppColors.contentBackground)
    .themeRefresh()
}
