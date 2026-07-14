//
//  TelemetryConsentView.swift
//  Pindrop
//
//  Created on 2026-07-14.
//

import AppKit
import Foundation
import SwiftUI

struct TelemetryConsentView: View {
    @ObservedObject var settings: SettingsStore
    let onResponse: (Bool) -> Void

    @Environment(\.locale) private var locale

    static let collectionDetailsURL = URL(
        string: "https://github.com/watzon/pindrop/blob/main/docs/TELEMETRY.md"
    )!

    var body: some View {
        ZStack {
            AppColors.windowBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text(localized("Help improve Pindrop?", locale: locale))
                    .font(FontLoader.font(family: .newsreader, size: 28, weight: .medium))
                    .tracking(-0.42)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(localized("Pindrop can send anonymous, privacy-preserving signals so bugs get fixed faster.", locale: locale))
                    .font(FontLoader.font(family: .inter, size: 12, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 18) {
                    ConsentItemRow(
                        symbolName: "chart.bar",
                        title: localized("Anonymous usage signals", locale: locale),
                        message: localized("App version, macOS version, hardware type, which features are used, and error categories.", locale: locale)
                    )
                    ConsentItemRow(
                        symbolName: "lock.shield",
                        title: localized("Your words stay yours", locale: locale),
                        message: localized("No transcripts, audio, prompts, file names, or personal content — ever.", locale: locale)
                    )
                    ConsentItemRow(
                        symbolName: "gearshape",
                        title: localized("You're in control", locale: locale),
                        message: localized("Change your choice anytime in Settings → Privacy.", locale: locale)
                    )
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Button {
                    NSWorkspace.shared.open(Self.collectionDetailsURL)
                } label: {
                    Text(localized("What does Pindrop collect?", locale: locale))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("consent.link.collectionDetails")
                .padding(.top, 14)

                VStack(spacing: 10) {
                    Button(localized("Share anonymous diagnostics", locale: locale)) {
                        onResponse(true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(ConsentPrimaryButtonStyle())
                    .accessibilityIdentifier("consent.button.accept")

                    Button(localized("Not now", locale: locale)) {
                        onResponse(false)
                    }
                    .buttonStyle(.plain)
                    .font(FontLoader.font(family: .inter, size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("consent.button.decline")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
            .padding(.top, 12)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 500)
        .environment(\.locale, settings.selectedAppLocale.locale)
        .environment(\.layoutDirection, settings.selectedAppLocale.layoutDirection)
        .themeRefresh()
    }
}

private struct ConsentItemRow: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.accentBackground)

                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FontLoader.font(family: .inter, size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(FontLoader.font(family: .inter, size: 12, weight: .regular))
                    .lineSpacing(6)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConsentPrimaryButtonStyle: ButtonStyle {
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
