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
        SettingsPaneStack {
            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Launch at Login", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: launchAtLoginBinding,
                        label: localized("Launch at Login", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.launchAtLogin")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Launch without showing window", locale: locale),
                        subtitle: localized("Start in the menu bar without opening the main window. You can still open it from the menu bar icon.", locale: locale)
                    )
                } control: {
                    SettingsToggle(
                        isOn: $settings.launchWithoutShowingWindow,
                        label: localized("Launch without showing window", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.launchWithoutShowingWindow")
                }

                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(title: localized("Show in Dock", locale: locale))
                } control: {
                    SettingsToggle(
                        isOn: $settings.showInDock,
                        label: localized("Show in Dock", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.showInDock")
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Interface Language", locale: locale))
                } control: {
                    Menu {
                        ForEach(AppLocale.allCases) { appLocale in
                            Button(interfaceLanguageLabel(appLocale)) {
                                settings.selectedAppLocale = appLocale
                            }
                        }
                    } label: {
                        SettingsMenuButton(title: interfaceLanguageLabel(settings.selectedAppLocale))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("settings.picker.interfaceLanguage")
                }
            }

            SettingsGroupCard {
                SettingsRow(showSeparator: true) {
                    SettingsRowLabel(
                        title: localized("Automatic updates", locale: locale),
                        subtitle: SettingsUpdateStatusPresentation.subtitle(
                            lastCheckDate: updateService.lastUpdateCheckDate,
                            canCheck: updateService.canCheckForUpdates,
                            locale: locale
                        )
                    )
                } control: {
                    SettingsToggle(
                        isOn: $automaticallyCheckForUpdates,
                        // Matches the visible row title (and its existing translations).
                        label: localized("Automatic updates", locale: locale)
                    )
                        .accessibilityIdentifier("settings.toggle.automaticUpdates")
                        .onChange(of: automaticallyCheckForUpdates) { _, newValue in
                            updateService.automaticallyChecksForUpdates = newValue
                        }
                }

                SettingsRow(showSeparator: false) {
                    SettingsRowLabel(title: localized("Check for updates", locale: locale))
                } control: {
                    HStack(spacing: 8) {
                        if AnnouncementCatalog.current != nil {
                            Button {
                                NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                            } label: {
                                SettingsMenuButton(
                                    title: localized("What's New…", locale: locale),
                                    showsChevron: false
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            updateService.checkForUpdates()
                        } label: {
                            SettingsMenuButton(
                                title: localized("Check Now", locale: locale),
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!updateService.canCheckForUpdates)
                    }
                }
            }

            SettingsDestructiveFooter(
                title: localized("Reset all settings…", locale: locale)
            ) {
                showingResetConfirmation = true
            }
            .accessibilityIdentifier("settings.button.resetAll")
        }
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
    .background(AppColors.windowBackground)
    .themeRefresh()
}
