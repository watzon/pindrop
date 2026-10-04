//
//  AnnouncementServiceTests.swift
//  PindropTests
//
//  Created on 2026-07-07.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class AnnouncementPresentationSpy: AnnouncementPresenting {
    private(set) var presentedAnnouncements: [Announcement] = []
    private var dismissalHandlers: [() -> Void] = []

    func showAnnouncement(
        _ announcement: Announcement,
        settings: SettingsStore,
        onDismiss: @escaping () -> Void
    ) {
        presentedAnnouncements.append(announcement)
        dismissalHandlers.append(onDismiss)
    }

    func dismissMostRecent() {
        dismissalHandlers.last?()
    }
}

@MainActor
@Suite(.serialized)
struct AnnouncementServiceTests {
    @Test func presentsWhenCatalogIDDiffersFromLastSeen() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "older")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        let didPresent = sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: true)

        #expect(didPresent)
        #expect(presenter.presentedAnnouncements.map(\.id) == ["current"])
    }

    @Test func skipsWhenCatalogIDMatchesLastSeen() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "current")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        let didPresent = sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: true)

        #expect(!didPresent)
        #expect(presenter.presentedAnnouncements.isEmpty)
    }

    @Test func marksSeenOnDismissNotOnPresent() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: true)

        #expect(settings.lastSeenAnnouncementID == "")

        presenter.dismissMostRecent()

        #expect(settings.lastSeenAnnouncementID == "current")
    }

    @Test func suppressesAutoPresentationBeforeOnboarding() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        let didPresent = sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: false)

        #expect(!didPresent)
        #expect(presenter.presentedAnnouncements.isEmpty)
    }

    @Test func suppressesAutoPresentationWhenTestModeGuardIsActive() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { true }
        )

        let didPresent = sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: true)

        #expect(!didPresent)
        #expect(presenter.presentedAnnouncements.isEmpty)
    }

    @Test func manualOpenWorksWhenAlreadySeen() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "current")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { true }
        )

        let didPresent = sut.showCurrentAnnouncement()

        #expect(didPresent)
        #expect(presenter.presentedAnnouncements.map(\.id) == ["current"])
    }

    @Test func onboardingCompletionMarksOrdinaryAnnouncementSeen() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "")
        defer { cleanup(settings) }
        let announcement = makeAnnouncement(id: "current")
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: AnnouncementPresentationSpy(),
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        sut.markCurrentAnnouncementSeen()

        #expect(settings.lastSeenAnnouncementID == "current")
    }

    @Test func onboardingCompletionKeepsNewInstallAnnouncementUnseen() {
        let settings = makeSettingsStore(lastSeenAnnouncementID: "")
        defer { cleanup(settings) }
        let presenter = AnnouncementPresentationSpy()
        var announcement = makeAnnouncement(id: "current")
        announcement.appliesToNewInstalls = true
        let sut = AnnouncementService(
            settingsStore: settings,
            presenter: presenter,
            currentAnnouncementProvider: { announcement },
            isAutoPresentationSuppressed: { false }
        )

        sut.markCurrentAnnouncementSeen()

        #expect(settings.lastSeenAnnouncementID == "")
        #expect(sut.presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: true))
        #expect(presenter.presentedAnnouncements.map(\.id) == ["current"])
    }

    @Test func currentAnnouncementPointsToSayso() throws {
        let announcement = try #require(AnnouncementCatalog.current)

        #expect(announcement.appliesToNewInstalls)
        #expect(announcement.action?.url.absoluteString == "https://justsayso.app")
    }

    private func makeSettingsStore(lastSeenAnnouncementID: String) -> SettingsStore {
        let settings = SettingsStore()
        cleanup(settings)
        settings.lastSeenAnnouncementID = lastSeenAnnouncementID
        return settings
    }

    private func cleanup(_ settings: SettingsStore) {
        settings.resetAllSettings()
        try? settings.deleteAPIEndpoint()
        try? settings.deleteAPIKey()
    }

    private func makeAnnouncement(id: String) -> Announcement {
        Announcement(
            id: id,
            titleKey: "Title",
            headerKey: "Header",
            subtitleKey: "Subtitle",
            footerKey: nil,
            items: []
        )
    }
}
