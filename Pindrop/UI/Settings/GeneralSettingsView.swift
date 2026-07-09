//
//  GeneralSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let launchAtLoginManager: LaunchAtLoginManager
    let updateService: UpdateService

    @Environment(\.locale) private var locale
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = true
    @State private var showingResetConfirmation = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    localized("Launch at Login", locale: locale),
                    isOn: launchAtLoginBinding
                )
                .accessibilityIdentifier("settings.toggle.launchAtLogin")

                Toggle(
                    localized("Show in Dock", locale: locale),
                    isOn: $settings.showInDock
                )
                .accessibilityIdentifier("settings.toggle.showInDock")
            } footer: {
                Text(localized("Choose whether Pindrop starts when you sign in and appears in the Dock.", locale: locale))
            }

            Section {
                Picker(
                    localized("Interface Language", locale: locale),
                    selection: interfaceLanguageBinding
                ) {
                    ForEach(AppLocale.allCases) { appLocale in
                        Text(interfaceLanguageLabel(appLocale))
                            .tag(appLocale)
                    }
                }
                .accessibilityIdentifier("settings.picker.interfaceLanguage")
            } header: {
                Text(localized("Language", locale: locale))
            } footer: {
                Text(localized("Changes the language used by Pindrop's interface.", locale: locale))
            }

            Section {
                Toggle(
                    localized("Automatic updates", locale: locale),
                    isOn: $automaticallyCheckForUpdates
                )
                .accessibilityIdentifier("settings.toggle.automaticUpdates")
                .onChange(of: automaticallyCheckForUpdates) { _, newValue in
                    updateService.automaticallyChecksForUpdates = newValue
                }

                LabeledContent(localized("Check for updates", locale: locale)) {
                    HStack {
                        if AnnouncementCatalog.current != nil {
                            Button(localized("What's New…", locale: locale)) {
                                NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                            }
                        }

                        Button(localized("Check Now", locale: locale)) {
                            updateService.checkForUpdates()
                        }
                        .disabled(!updateService.canCheckForUpdates)
                    }
                }
            } header: {
                Text(localized("Updates", locale: locale))
            } footer: {
                Text(localized("Keep Pindrop current automatically, or check for a new version now.", locale: locale))
            }

            Section {
                Button(localized("Reset All Settings…", locale: locale), role: .destructive) {
                    showingResetConfirmation = true
                }
                .accessibilityIdentifier("settings.button.resetAll")
            } header: {
                Text(localized("Reset", locale: locale))
            } footer: {
                Text(localized("Clears preferences and restarts onboarding.", locale: locale))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            synchronizeLaunchAtLoginState()
            updateService.automaticallyChecksForUpdates = automaticallyCheckForUpdates
        }
        .alert(
            localized("Reset All Settings?", locale: locale),
            isPresented: $showingResetConfirmation
        ) {
            Button(localized("Cancel", locale: locale), role: .cancel) {}
            Button(localized("Reset", locale: locale), role: .destructive) {
                settings.resetAllSettings()
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(localized("This will clear all your settings including API keys and restart onboarding", locale: locale))
        }
        .alert(
            localized("Launch at Login Could Not Be Changed", locale: locale),
            isPresented: Binding(
                get: { launchAtLoginError != nil },
                set: { if !$0 { launchAtLoginError = nil } }
            )
        ) {
            Button(localized("OK", locale: locale), role: .cancel) {}
        } message: {
            if let launchAtLoginError {
                Text(launchAtLoginError)
            }
        }
    }

    private var interfaceLanguageBinding: Binding<AppLocale> {
        Binding(
            get: { settings.selectedAppLocale },
            set: { settings.selectedAppLocale = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { updateLaunchAtLogin($0) }
        )
    }

    private func interfaceLanguageLabel(_ appLocale: AppLocale) -> String {
        let displayName = appLocale.pickerLabel(locale: locale)
        guard let nativeName = appLocale.nativeDisplayName(currentLocale: locale) else {
            return displayName
        }
        return "\(displayName) — \(nativeName)"
    }

    private func synchronizeLaunchAtLoginState() {
        let actualState = launchAtLoginManager.isEnabled
        guard settings.launchAtLogin != actualState else { return }
        settings.launchAtLogin = actualState
        Log.app.info("Synced launch at login setting from system state: \(actualState)")
    }

    private func updateLaunchAtLogin(_ requestedState: Bool) {
        do {
            try launchAtLoginManager.setEnabled(requestedState)
        } catch {
            Log.app.error("Failed to change launch at login from Settings: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
        }

        let actualState = launchAtLoginManager.isEnabled
        settings.launchAtLogin = actualState
        if actualState != requestedState {
            Log.app.warning(
                "Launch at login requested=\(requestedState) actual=\(actualState); restored UI to system state"
            )
        }
    }
}

#Preview {
    GeneralSettingsView(
        settings: SettingsStore(),
        launchAtLoginManager: LaunchAtLoginManager(),
        updateService: UpdateService()
    )
    .frame(width: 620, height: 560)
}
