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
        id: "2026.07-v1.21",
        titleKey: "What's new",
        headerKey: "Pindrop 1.21.0 · July 2026",
        subtitleKey: "A new local engine, three new languages, and more control over every dictation.",
        footerKey: "Also: cancel a dictation mid-flight with a hotkey, launch silently to the menu bar, and type reliably into virtual machines.",
        items: [
            AnnouncementItem(
                id: "sensevoice",
                visual: .symbol("waveform"),
                titleKey: "SenseVoice transcription",
                bodyKey: "A new fully local engine with fast, accurate multilingual recognition.",
                credit: nil
            ),
            AnnouncementItem(
                id: "indicators",
                visual: .symbol("rectangle.topthird.inset.filled"),
                titleKey: "Notch and caret indicators",
                bodyKey: "Choose a discreet pill under the notch or a bubble that follows your caret.",
                credit: nil
            ),
            AnnouncementItem(
                id: "languages",
                visual: .symbol("globe"),
                titleKey: "Three new languages",
                bodyKey: "Dictate in Polish, Hindi, and Malayalam. The interface now speaks Polish too.",
                credit: nil
            ),
            AnnouncementItem(
                id: "formatting",
                visual: .symbol("text.alignleft"),
                titleKey: "Cleaner transcripts",
                bodyKey: "Long dictations can now break into readable paragraphs, entirely on device.",
                credit: nil
            ),
        ]
    )
}
