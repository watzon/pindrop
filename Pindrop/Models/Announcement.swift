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
    static let current: Announcement? = Announcement(
        id: "2026.07-v0.10",
        titleKey: "What's new",
        headerKey: "Pindrop 0.10.0 · July 2026",
        subtitleKey: "Replay, a new look, and keyboard control throughout Pindrop.",
        footerKey: nil,
        items: [
            AnnouncementItem(
                id: "replay",
                visual: .symbol("play.fill"),
                titleKey: "Replay every dictation",
                bodyKey: "Pindrop can keep audio for seven days, so you can listen back from your Library whenever you need it.",
                credit: nil
            ),
            AnnouncementItem(
                id: "new-look",
                visual: .symbol("paintbrush.fill"),
                titleKey: "A new look",
                bodyKey: "A warmer, quieter design puts your words first. Your theme presets carry over — plus a new default, Library.",
                credit: nil
            ),
            AnnouncementItem(
                id: "keyboard-everywhere",
                visual: .symbol("keyboard"),
                titleKey: "Keyboard everywhere",
                bodyKey: "Navigate pages, search, create notes, export, and delete without leaving the keyboard.",
                credit: nil
            ),
        ]
    )
}
