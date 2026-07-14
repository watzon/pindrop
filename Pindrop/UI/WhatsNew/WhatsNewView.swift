//
//  WhatsNewView.swift
//  Pindrop
//
//  Created on 2026-07-07.
//

import Foundation
import SwiftUI

struct WhatsNewView: View {
    let announcement: Announcement
    @ObservedObject var settings: SettingsStore
    let onDismiss: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(localized(announcement.titleKey, locale: locale))
                    .font(FontLoader.font(family: .newsreader, size: 28, weight: .medium))
                    .tracking(-0.42)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(localized(announcement.headerKey, locale: locale))
                    .font(AppTypography.monoTime)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(announcement.items) { item in
                        AnnouncementItemRow(item: item)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

                if let footerKey = announcement.footerKey {
                    Text(localized(footerKey, locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                HStack {
                    Spacer()

                    Button(localized("Continue", locale: locale)) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(WhatsNewPrimaryButtonStyle())
                    Spacer()
                }
                .padding(.top, 16)
            }
            .padding(.top, 12)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 560)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .themeRefresh()
    }
}

private struct AnnouncementItemRow: View {
    let item: AnnouncementItem

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AnnouncementVisualView(visual: item.visual)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(localized(item.titleKey, locale: locale))
                    .font(FontLoader.font(family: .inter, size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localized(item.bodyKey, locale: locale))
                    .font(FontLoader.font(family: .inter, size: 12, weight: .regular))
                    .lineSpacing(6)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let credit = item.credit {
                    AnnouncementCreditView(credit: credit)
                        .padding(.top, AppTheme.Spacing.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnnouncementVisualView: View {
    let visual: AnnouncementItem.Visual

    var body: some View {
        switch visual {
        case .symbol(let symbolName):
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.accentBackground)

                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }

        case .orbDemo:
            AnnouncementOrbDemoView()
        }
    }
}

private struct WhatsNewPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FontLoader.font(family: .inter, size: 13, weight: .semibold))
            .foregroundStyle(AppColors.contentBackground)
            .padding(.vertical, 9)
            .padding(.horizontal, 26)
            .background(AppColors.accent.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AnnouncementCreditView: View {
    let credit: AnnouncementCredit

    @Environment(\.locale) private var locale

    private var label: String {
        String(format: localized(credit.labelKey, locale: locale), credit.name)
    }

    var body: some View {
        Group {
            if let url = credit.url {
                Link(destination: url) {
                    creditLabel
                }
                .buttonStyle(.plain)
            } else {
                creditLabel
            }
        }
    }

    private var creditLabel: some View {
        Text(label)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Compact Orb preview for What's New. The synthetic meter is polled from the
/// production waveform timeline, with no second timer or published-state churn.
@MainActor
private struct AnnouncementOrbDemoView: View {
    /// Non-publishing sample holder so EMA smoothing survives across timeline
    /// ticks without an `ObservableObject` invalidating the demo chrome.
    @State private var sampler = AnnouncementOrbDemoSampler()

    var body: some View {
        let palette = OrbWaveformPalette.forPresetID("library")
        ZStack {
            OrbGlassFillView(
                palette: palette,
                sample: { date in sampler.sample(at: date) },
                isHovered: true,
                isRecording: true,
                isProcessing: false,
                isMuted: false
            )

            Circle()
                .strokeBorder(OrbPalette.rimSoft, lineWidth: 1)
        }
        .clipShape(Circle())
        .shadow(color: palette.glowColor.opacity(0.30), radius: 12, x: 0, y: 4)
        .onDisappear {
            sampler.reset()
        }
        .allowsHitTesting(false)
    }
}

/// Generates the demo's speech-like meter curve and applies the same light EMA
/// ballistics production meters use, polled only from the waveform timeline.
@MainActor
private final class AnnouncementOrbDemoSampler {
    private var audioLevel: Float = 0
    private var bandLevels = AudioBandLevels.zero
    private static let meterEpsilon: Float = 0.005

    func sample(at date: Date) -> (bands: AudioBandLevels, overall: Float) {
        let t = date.timeIntervalSinceReferenceDate
        let phrase = max(0.0, sin(t * 1.85))
        let syllable = 0.5 + 0.5 * sin(t * 9.2 + sin(t * 1.7))
        let shimmer = 0.5 + 0.5 * sin(t * 14.5)
        let level = clamped(0.24 + phrase * 0.38 + syllable * 0.26)

        updateAudioLevel(Float(level))
        updateBandLevels(
            AudioBandLevels(
                low: Float(clamped(level * (0.78 + 0.18 * sin(t * 2.4)))),
                mid: Float(clamped(0.20 + syllable * 0.58)),
                high: Float(clamped(0.14 + shimmer * 0.44))
            )
        )
        return (bandLevels, audioLevel)
    }

    func reset() {
        audioLevel = 0
        bandLevels = .zero
    }

    private func updateAudioLevel(_ level: Float) {
        let smoothed = min(1.0, max(0.0, audioLevel * 0.3 + level * 0.7))
        if abs(smoothed - audioLevel) < Self.meterEpsilon {
            return
        }
        audioLevel = smoothed
    }

    private func updateBandLevels(_ levels: AudioBandLevels) {
        func smooth(_ old: Float, _ new: Float) -> Float {
            min(1.0, max(0.0, old * 0.3 + new * 0.7))
        }
        let next = AudioBandLevels(
            low: smooth(bandLevels.low, levels.low),
            mid: smooth(bandLevels.mid, levels.mid),
            high: smooth(bandLevels.high, levels.high)
        )
        if abs(next.low - bandLevels.low) < Self.meterEpsilon,
           abs(next.mid - bandLevels.mid) < Self.meterEpsilon,
           abs(next.high - bandLevels.high) < Self.meterEpsilon {
            return
        }
        bandLevels = next
    }

    private func clamped(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
