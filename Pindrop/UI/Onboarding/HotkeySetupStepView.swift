//
//  HotkeySetupStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI

struct HotkeySetupStepView: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            VStack(spacing: 16) {
                hotkeyCard(
                    title: localized("Toggle Recording", locale: locale),
                    description: localized("Press once to start, again to stop", locale: locale),
                    hotkey: settings.toggleHotkey,
                    icon: .record
                )

                hotkeyCard(
                    title: localized("Push-to-Talk", locale: locale),
                    description: localized("Hold to record, release to transcribe", locale: locale),
                    hotkey: settings.pushToTalkHotkey,
                    icon: .hand
                )

                hotkeyCard(
                    title: localized("Copy Last Transcript", locale: locale),
                    description: localized("Quickly copy your last transcription", locale: locale),
                    hotkey: settings.copyLastTranscriptHotkey,
                    icon: .copy
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            infoSection

            actionButtons
        }
        .padding(.vertical, 24)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            IconView(icon: .keyboard, size: 40)
                .foregroundStyle(AppColors.accent)
                .padding(.bottom, 8)

            Text(localized("Keyboard Shortcuts", locale: locale))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(localized("Your hotkeys are ready to use.\nYou can customize them later in Settings.", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private func hotkeyCard(title: String, description: String, hotkey: String, icon: Icon) -> some View {
        HStack(spacing: 16) {
            IconView(icon: icon, size: 24)
                .foregroundStyle(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(AppColors.accent.opacity(0.1))
                .background(.ultraThinMaterial, in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(hotkey.isEmpty ? localized("Not Set", locale: locale) : hotkey)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    private var infoSection: some View {
        HStack(spacing: 12) {
            IconView(icon: .info, size: 16)
                .foregroundStyle(.secondary)

            Text(localized("You can change these anytime from the menu bar → Settings → Hotkeys", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(localized("Skip for Now", locale: locale), action: onSkip)
                .buttonStyle(.bordered)

            Button(action: onContinue) {
                Text(localized("Continue", locale: locale))
                    .font(.headline)
                    .frame(maxWidth: 180)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 40)
    }
}

#if DEBUG
struct HotkeySetupStepView_Previews: PreviewProvider {
    static var previews: some View {
        HotkeySetupStepView(
            settings: SettingsStore(),
            onContinue: {},
            onSkip: {}
        )
        .frame(width: 800, height: 600)
    }
}
#endif
