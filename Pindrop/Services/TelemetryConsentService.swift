//
//  TelemetryConsentService.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  One-time telemetry consent prompt, mirroring AnnouncementService. The prompt is
//  versioned: bump `currentConsentVersion` if the collection scope ever changes so
//  users are asked again. Declining (or closing the window) keeps telemetry off.
//

import Foundation

@MainActor
protocol TelemetryConsentPresenting: AnyObject {
    func showConsent(
        settings: SettingsStore,
        onResponse: @escaping (Bool) -> Void
    )
}

@MainActor
final class TelemetryConsentService {
    static let currentConsentVersion = 1

    private let settingsStore: SettingsStore
    private let presenter: TelemetryConsentPresenting
    private let isAutoPresentationSuppressed: () -> Bool
    private let isTelemetryConfigured: () -> Bool

    init(
        settingsStore: SettingsStore,
        presenter: TelemetryConsentPresenting,
        isAutoPresentationSuppressed: @escaping () -> Bool = { AppTestMode.isRunningAnyTests },
        isTelemetryConfigured: @escaping () -> Bool = { !TelemetryService.telemetryDeckAppID.isEmpty }
    ) {
        self.settingsStore = settingsStore
        self.presenter = presenter
        self.isAutoPresentationSuppressed = isAutoPresentationSuppressed
        self.isTelemetryConfigured = isTelemetryConfigured
    }

    @discardableResult
    func presentConsentIfNeeded(
        hasCompletedOnboarding: Bool,
        onResponse: ((Bool) -> Void)? = nil
    ) -> Bool {
        guard hasCompletedOnboarding else {
            Log.telemetry.debug("Consent prompt skipped before onboarding completion")
            return false
        }

        guard !isAutoPresentationSuppressed() else {
            Log.telemetry.debug("Consent prompt suppressed")
            return false
        }

        guard isTelemetryConfigured() else {
            Log.telemetry.debug("Consent prompt skipped: no TelemetryDeck app ID configured")
            return false
        }

        guard settingsStore.telemetryConsentPromptVersion < Self.currentConsentVersion else {
            Log.telemetry.debug("Consent prompt skipped: already answered for current version")
            return false
        }

        Log.telemetry.infoVisible("Presenting telemetry consent prompt version=\(Self.currentConsentVersion)")
        presenter.showConsent(settings: settingsStore) { [weak self] accepted in
            self?.recordResponse(accepted: accepted)
            onResponse?(accepted)
        }
        return true
    }

    private func recordResponse(accepted: Bool) {
        settingsStore.telemetryEnabled = accepted
        settingsStore.telemetryConsentPromptVersion = Self.currentConsentVersion
        Log.telemetry.infoVisible("Telemetry consent recorded accepted=\(accepted)")
    }

    /// Marks consent as handled by the onboarding flow, which presents its own
    /// toggle on the permissions step — fresh installs must never also get the
    /// standalone prompt. `telemetryEnabled` itself is bound directly to the
    /// onboarding toggle; only the version stamp happens here. No-op when
    /// telemetry is unconfigured (forks without an app ID) so those users are
    /// still asked if an app ID appears in a later build.
    static func markConsentHandledDuringOnboarding(
        settings: SettingsStore,
        isTelemetryConfigured: Bool = !TelemetryService.telemetryDeckAppID.isEmpty
    ) {
        guard isTelemetryConfigured else { return }
        settings.telemetryConsentPromptVersion = currentConsentVersion
        Log.telemetry.infoVisible(
            "Telemetry consent handled during onboarding enabled=\(settings.telemetryEnabled)"
        )
    }
}
