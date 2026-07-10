//
//  ReadyStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct ReadyStepView: View {
    @ObservedObject var settings: SettingsStore
    var modelManager: ModelManager
    let selectedModelName: String
    let onComplete: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            IconView(icon: .check, size: 40)
                .foregroundStyle(AppColors.accent)
                .frame(width: 84, height: 84)
                .background(AppColors.accentBackground, in: .circle)
                .padding(.bottom, 24)

            Text(localized("You're set.", locale: locale))
                .font(OnboardingType.bigHeading)
                .tracking(-0.8)
                .foregroundStyle(AppColors.textPrimary)

            instructionLine
                .font(OnboardingType.welcomeSubtitle)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 14)

            OnboardingPrimaryButton(
                title: localized("Try it now", locale: locale),
                icon: .mic,
                action: onComplete
            )
            .padding(.top, 30)
        }
    }

    /// One localized format string split around the kbd chip so locales control
    /// word order (e.g. Japanese puts the verb after the shortcut).
    private var instructionLine: some View {
        let format = localized(
            "Press %@ and start talking — Pindrop types wherever your cursor is.",
            locale: locale
        )
        let parts = format.components(separatedBy: "%@")
        let prefix = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let suffix = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : ""

        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            if !prefix.isEmpty {
                Text(prefix)
            }
            finaleKbdChip
            if !suffix.isEmpty {
                Text(suffix)
            }
        }
    }

    /// §14 finale chip: page bg, radius 6, padding 2/8, JetBrains Mono 12 · 500 ink.
    private var finaleKbdChip: some View {
        Text(settings.toggleHotkey.isEmpty
            ? localized("Not Set", locale: locale)
            : settings.toggleHotkey)
            .font(FontLoader.font(family: .jetbrainsMono, size: 12, weight: .medium))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppColors.contentBackground)
            )
    }
}

#if DEBUG
struct ReadyStepView_Previews: PreviewProvider {
    static var previews: some View {
        ReadyStepView(
            settings: SettingsStore(),
            modelManager: PreviewModelManagerReady(),
            selectedModelName: "openai_whisper-base.en",
            onComplete: {}
        )
        .frame(width: 760, height: 500)
        .background(AppColors.windowBackground)
    }
}

final class PreviewModelManagerReady: ModelManager {
    override init() {}
}
#endif
