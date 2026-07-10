//
//  WelcomeStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            medallion

            Text(localized("Welcome to Pindrop", locale: locale))
                .font(OnboardingType.bigHeading)
                .tracking(-0.8)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Local speech-to-text, right from your menu bar.\nFast, private, and always available.", locale: locale))
                .font(OnboardingType.welcomeSubtitle)
                .lineSpacing(8)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 12)

            OnboardingPrimaryButton(
                title: localized("Get Started", locale: locale),
                icon: .arrowRight,
                action: onContinue
            )
            .padding(.top, 30)
        }
    }

    private var medallion: some View {
        IconView(icon: .mic, size: 40)
            .foregroundStyle(AppColors.contentBackground)
            .frame(width: 84, height: 84)
            .background(AppColors.accent, in: .rect(cornerRadius: 24))
            .padding(.bottom, 26)
    }
}

#if DEBUG
struct WelcomeStepView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeStepView(onContinue: {})
            .frame(width: 760, height: 500)
            .background(AppColors.windowBackground)
    }
}
#endif
