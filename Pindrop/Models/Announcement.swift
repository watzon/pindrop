//
//  Announcement.swift
//  Pindrop
//
//  Created on 2026-07-07.
//

import Foundation

struct Announcement: Identifiable {
    let id: String
    let titleKey: String
    let headerKey: String
    let subtitleKey: String
    let footerKey: String?
    let items: [AnnouncementItem]
    /// Optional call to action. When set, the window shows it as the primary button.
    var action: AnnouncementAction? = nil
    /// When true, completing onboarding does not mark the announcement as seen,
    /// so new installs also get it on their next launch.
    var appliesToNewInstalls = false
}

struct AnnouncementAction {
    let titleKey: String
    let url: URL
}

struct AnnouncementItem: Identifiable {
    enum Visual {
        case symbol(String)
        case orbDemo
    }

    let id: String
    let visual: Visual
    let titleKey: String
    let bodyKey: String
    let credit: AnnouncementCredit?
}

struct AnnouncementCredit {
    let name: String
    let url: URL?
    let labelKey: String
}

enum AnnouncementCatalog {
    static let saysoURL = URL(string: "https://justsayso.app")!

    static let current: Announcement? = Announcement(
        id: "2026.10-v1.23-discontinued",
        titleKey: "Pindrop is discontinued",
        headerKey: "Pindrop 1.23.0 · Final release",
        subtitleKey: "Pindrop 1.23.0 is the final release. Sayso is its replacement.",
        footerKey: "Download Sayso at justsayso.app.",
        items: [
            AnnouncementItem(
                id: "replacement",
                visual: .symbol("arrow.right.circle"),
                titleKey: "Sayso replaces Pindrop",
                bodyKey: "Sayso is the new dictation app from the developer of Pindrop. It runs on macOS, Windows, and Linux. Sayso can import your Pindrop dictations, dictionary, and prompt presets.",
                credit: nil
            ),
            AnnouncementItem(
                id: "end-of-updates",
                visual: .symbol("clock.badge.xmark"),
                titleKey: "No more updates",
                bodyKey: "This is the final release. Pindrop gets no new features, fixes, or support after it.",
                credit: nil
            ),
            AnnouncementItem(
                id: "still-works",
                visual: .symbol("checkmark.circle"),
                titleKey: "Pindrop keeps working",
                bodyKey: "You can continue to use this version. Your transcripts, notes, and settings stay on your Mac.",
                credit: nil
            ),
            AnnouncementItem(
                id: "source",
                visual: .symbol("archivebox"),
                titleKey: "The source code stays available",
                bodyKey: "The Pindrop repository on GitHub is archived and read-only.",
                credit: nil
            ),
        ],
        action: AnnouncementAction(titleKey: "Get Sayso", url: saysoURL),
        appliesToNewInstalls: true
    )
}
