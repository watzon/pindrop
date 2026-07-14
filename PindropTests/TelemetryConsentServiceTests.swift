//
//  TelemetryConsentServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-14.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class TelemetryConsentPresentationSpy: TelemetryConsentPresenting {
    private(set) var presentationCount = 0
    private var responseHandlers: [(Bool) -> Void] = []

    func showConsent(
        settings: SettingsStore,
        onResponse: @escaping (Bool) -> Void
    ) {
        presentationCount += 1
        responseHandlers.append(onResponse)
    }

    func respondMostRecent(accepted: Bool) {
        responseHandlers.last?(accepted)
    }
}

@MainActor
@Suite(.serialized)
struct TelemetryConsentServiceTests {
    @Test func presentsWhenConsentVersionUnanswered() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        let didPresent = sut.presentConsentIfNeeded(hasCompletedOnboarding: true)

        #expect(didPresent)
        #expect(presenter.presentationCount == 1)
    }

    @Test func skipsBeforeOnboardingCompletion() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        let didPresent = sut.presentConsentIfNeeded(hasCompletedOnboarding: false)

        #expect(!didPresent)
        #expect(presenter.presentationCount == 0)
    }

    @Test func skipsWhenSuppressed() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter, isSuppressed: { true })

        let didPresent = sut.presentConsentIfNeeded(hasCompletedOnboarding: true)

        #expect(!didPresent)
    }

    @Test func skipsWhenTelemetryUnconfigured() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter, isConfigured: { false })

        let didPresent = sut.presentConsentIfNeeded(hasCompletedOnboarding: true)

        #expect(!didPresent)
    }

    @Test func skipsWhenCurrentVersionAlreadyAnswered() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryConsentPromptVersion = TelemetryConsentService.currentConsentVersion
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        let didPresent = sut.presentConsentIfNeeded(hasCompletedOnboarding: true)

        #expect(!didPresent)
    }

    @Test func acceptingEnablesTelemetryAndStampsVersion() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        sut.presentConsentIfNeeded(hasCompletedOnboarding: true)
        presenter.respondMostRecent(accepted: true)

        #expect(settings.telemetryEnabled == true)
        #expect(settings.telemetryConsentPromptVersion == TelemetryConsentService.currentConsentVersion)
    }

    @Test func decliningKeepsTelemetryOffAndStampsVersion() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        sut.presentConsentIfNeeded(hasCompletedOnboarding: true)
        presenter.respondMostRecent(accepted: false)

        #expect(settings.telemetryEnabled == false)
        #expect(settings.telemetryConsentPromptVersion == TelemetryConsentService.currentConsentVersion)

        // Never re-presents after a recorded answer.
        let didPresentAgain = sut.presentConsentIfNeeded(hasCompletedOnboarding: true)
        #expect(!didPresentAgain)
    }

    @Test func forwardsResponseToCaller() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)

        var forwarded: Bool?
        sut.presentConsentIfNeeded(hasCompletedOnboarding: true) { accepted in
            forwarded = accepted
        }
        presenter.respondMostRecent(accepted: true)

        #expect(forwarded == true)
        // Settings are recorded before the caller's handler runs.
        #expect(settings.telemetryEnabled == true)
    }

    @Test func onboardingStampSuppressesPromptWithoutTouchingChoice() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }
        settings.telemetryEnabled = true

        TelemetryConsentService.markConsentHandledDuringOnboarding(
            settings: settings,
            isTelemetryConfigured: true
        )

        #expect(settings.telemetryConsentPromptVersion == TelemetryConsentService.currentConsentVersion)
        #expect(settings.telemetryEnabled == true)

        let presenter = TelemetryConsentPresentationSpy()
        let sut = makeService(settings: settings, presenter: presenter)
        #expect(!sut.presentConsentIfNeeded(hasCompletedOnboarding: true))
    }

    @Test func onboardingStampIsNoOpWhenTelemetryUnconfigured() {
        let settings = makeSettingsStore()
        defer { cleanup(settings) }

        TelemetryConsentService.markConsentHandledDuringOnboarding(
            settings: settings,
            isTelemetryConfigured: false
        )

        #expect(settings.telemetryConsentPromptVersion == 0)
    }

    // MARK: - Helpers

    private func makeService(
        settings: SettingsStore,
        presenter: TelemetryConsentPresentationSpy,
        isSuppressed: @escaping () -> Bool = { false },
        isConfigured: @escaping () -> Bool = { true }
    ) -> TelemetryConsentService {
        TelemetryConsentService(
            settingsStore: settings,
            presenter: presenter,
            isAutoPresentationSuppressed: isSuppressed,
            isTelemetryConfigured: isConfigured
        )
    }

    private func makeSettingsStore() -> SettingsStore {
        let settings = SettingsStore()
        cleanup(settings)
        return settings
    }

    private func cleanup(_ settings: SettingsStore) {
        settings.resetAllSettings()
        try? settings.deleteAPIEndpoint()
        try? settings.deleteAPIKey()
    }
}
