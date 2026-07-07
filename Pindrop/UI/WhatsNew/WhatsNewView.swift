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

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        ForEach(announcement.items) { item in
                            AnnouncementItemRow(item: item)
                        }

                        if let footerKey = announcement.footerKey {
                            Text(localized(footerKey, locale: locale))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, AppTheme.Spacing.xs)
                        }
                    }
                    .padding(.bottom, AppTheme.Spacing.xs)
                }

                HStack {
                    Spacer()

                    Button(localized("Continue", locale: locale)) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(AppTheme.Spacing.xxl)
        }
        .frame(width: 520, height: 640)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .themeRefresh()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(localized(announcement.titleKey, locale: locale))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accent)
                .textCase(.uppercase)

            Text(localized(announcement.headerKey, locale: locale))
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(localized(announcement.subtitleKey, locale: locale))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AnnouncementItemRow: View {
    let item: AnnouncementItem

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            AnnouncementVisualView(visual: item.visual)
                .frame(width: 76, height: 76)
                .padding(.top, AppTheme.Spacing.xxs)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(localized(item.titleKey, locale: locale))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localized(item.bodyKey, locale: locale))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let credit = item.credit {
                    AnnouncementCreditView(credit: credit)
                        .padding(.top, AppTheme.Spacing.xxs)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppColors.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .strokeBorder(AppColors.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(AppTheme.Shadow.sm)
    }
}

private struct AnnouncementVisualView: View {
    let visual: AnnouncementItem.Visual

    var body: some View {
        switch visual {
        case .symbol(let symbolName):
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppColors.accentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .strokeBorder(AppColors.border.opacity(0.55), lineWidth: 1)
                    )

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }

        case .orbDemo:
            AnnouncementOrbDemoView()
        }
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
            updateSyntheticLevels(at: date)
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
