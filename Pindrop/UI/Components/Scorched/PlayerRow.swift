//
//  PlayerRow.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Shared player chrome (spec §6): 44 pt play circle, waveform, elapsed/total, speed chip.
//

import SwiftUI

/// Scorched Earth player row used by Library expanded cards and meeting detail.
struct PlayerRow: View {
    let peaks: [Float]
    /// 0…1 playback progress.
    var progress: Double
    var isPlaying: Bool
    var elapsedTotalLabel: String
    var rateLabel: String
    var onTogglePlay: () -> Void
    var onSeek: (Double) -> Void
    var onCycleRate: () -> Void
    var rateHelp: String? = nil

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onTogglePlay) {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.contentBackground)
                            .offset(x: isPlaying ? 0 : 1)
                    }
            }
            .buttonStyle(.plain)
            .keyboardFocusRing(Circle())
            .accessibilityLabel(localized(isPlaying ? "Pause" : "Play", locale: locale))

            WaveformView(
                peaks: peaks,
                progress: progress,
                onSeek: onSeek
            )
            .frame(maxWidth: .infinity)

            Text(elapsedTotalLabel)
                .font(AppTypography.monoTime)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
                .fixedSize()

            Button(action: onCycleRate) {
                Text(rateLabel)
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .overlay(
                        Capsule().strokeBorder(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(rateHelp ?? "")
            .keyboardFocusRing(Capsule())
            .accessibilityLabel(localized("Playback speed", locale: locale))
            .accessibilityValue(rateLabel)
        }
        .frame(height: 44)
    }
}

#Preview("PlayerRow") {
    PlayerRow(
        peaks: (0..<40).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) * 0.4))) },
        progress: 0.35,
        isPlaying: false,
        elapsedTotalLabel: "0:12 / 0:31",
        rateLabel: "1×",
        onTogglePlay: {},
        onSeek: { _ in },
        onCycleRate: {}
    )
    .padding()
    .background(AppColors.windowBackground)
    .themeRefresh()
}
