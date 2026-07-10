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

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(localized("Press", locale: locale))
                SettingsKbdChip(text: settings.toggleHotkey.isEmpty
                    ? localized("Not Set", locale: locale)
                    : settings.toggleHotkey)
                Text(localized("and start talking — Pindrop types wherever your cursor is.", locale: locale))
            }
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
