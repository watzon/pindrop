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
                trafficLights
                    .padding(.bottom, 20)

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
            .padding(.top, 20)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 540)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .themeRefresh()
    }

    private var trafficLights: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Circle()
                    .fill(Color(nsColor: NSColor(pindropHex: "#FF5F57") ?? .systemRed))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Close", locale: locale))

            Circle()
                .fill(Color(nsColor: NSColor(pindropHex: "#E9E5DA") ?? .lightGray))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Circle()
                .fill(Color(nsColor: NSColor(pindropHex: "#E9E5DA") ?? .lightGray))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
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

@MainActor
private struct AnnouncementOrbDemoView: View {
    @StateObject private var state = FloatingIndicatorState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            OrbPalette.surface.opacity(0.96),
                            OrbPalette.depthTint,
                            OrbPalette.surface
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 44
                    )
                )

            Circle()
                .strokeBorder(OrbPalette.rimSoft, lineWidth: 1)

            OrbBlobsView(state: state, isLive: true, isExcited: true)
                .padding(5)
                .clipShape(Circle())
        }
        .shadow(color: OrbPalette.bandMid.opacity(0.30), radius: 12, x: 0, y: 4)
        .onReceive(timer) { date in
            if !reduceMotion {
                updateSyntheticLevels(at: date)
            }
        }
        .onDisappear {
            state.updateAudioLevel(0)
            state.updateBandLevels(.zero)
        }
        .allowsHitTesting(false)
    }

    private func updateSyntheticLevels(at date: Date) {
        let t = date.timeIntervalSinceReferenceDate
        let phrase = max(0.0, sin(t * 1.85))
        let syllable = 0.5 + 0.5 * sin(t * 9.2 + sin(t * 1.7))
        let shimmer = 0.5 + 0.5 * sin(t * 14.5)
        let level = clamped(0.24 + phrase * 0.38 + syllable * 0.26)

        state.updateAudioLevel(Float(level))
        state.updateBandLevels(
            AudioBandLevels(
                low: Float(clamped(level * (0.78 + 0.18 * sin(t * 2.4)))),
                mid: Float(clamped(0.20 + syllable * 0.58)),
                high: Float(clamped(0.14 + shimmer * 0.44))
            )
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
