//
//  AnnouncementService.swift
//  Pindrop
//
//  Created on 2026-07-07.
//

import Foundation

@MainActor
protocol AnnouncementPresenting: AnyObject {
    func showAnnouncement(
        _ announcement: Announcement,
        settings: SettingsStore,
        onDismiss: @escaping () -> Void
    )
}

@MainActor
final class AnnouncementService {
    private let settingsStore: SettingsStore
    private let presenter: AnnouncementPresenting
    private let currentAnnouncementProvider: () -> Announcement?
    private let isAutoPresentationSuppressed: () -> Bool

    init(
        settingsStore: SettingsStore,
        presenter: AnnouncementPresenting,
        currentAnnouncementProvider: @escaping () -> Announcement? = { AnnouncementCatalog.current },
        isAutoPresentationSuppressed: @escaping () -> Bool = { AppTestMode.isRunningAnyTests }
    ) {
        self.settingsStore = settingsStore
        self.presenter = presenter
        self.currentAnnouncementProvider = currentAnnouncementProvider
        self.isAutoPresentationSuppressed = isAutoPresentationSuppressed
    }

    @discardableResult
    func presentCurrentAnnouncementIfNeeded(hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding else {
            Log.app.debug("Announcement auto-presentation skipped before onboarding completion")
            return false
        }

        guard !isAutoPresentationSuppressed() else {
            Log.app.debug("Announcement auto-presentation suppressed")
            return false
        }

        guard let announcement = currentAnnouncementProvider() else {
            Log.app.debug("Announcement auto-presentation skipped because catalog is empty")
            return false
        }

        guard settingsStore.lastSeenAnnouncementID != announcement.id else {
            Log.app.debug("Announcement auto-presentation skipped because id is already seen")
            return false
        }

        present(announcement)
        return true
    }

    @discardableResult
    func showCurrentAnnouncement() -> Bool {
        guard let announcement = currentAnnouncementProvider() else {
            Log.app.debug("Manual announcement presentation skipped because catalog is empty")
            return false
        }

        present(announcement)
        return true
    }

    func markCurrentAnnouncementSeen() {
        guard let announcement = currentAnnouncementProvider() else { return }
        markSeen(announcement)
    }

    private func present(_ announcement: Announcement) {
        Log.ui.infoVisible("Presenting announcement id=\(announcement.id)")
        presenter.showAnnouncement(announcement, settings: settingsStore) { [weak self] in
            self?.markSeen(announcement)
        }
    }

    private func markSeen(_ announcement: Announcement) {
        guard settingsStore.lastSeenAnnouncementID != announcement.id else { return }
        settingsStore.lastSeenAnnouncementID = announcement.id
        Log.app.infoVisible("Marked announcement seen id=\(announcement.id)")
    }
}
