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
        id: "2026.07-v1.19",
        titleKey: "What's New in Pindrop",
        headerKey: "Pindrop 1.19",
        subtitleKey: "A big round of upgrades — and two community shout-outs.",
        footerKey: "Also new: RTL layout support and 20 new interface languages.",
        items: [
            AnnouncementItem(
                id: "orb",
                visual: .orbDemo,
                titleKey: "Meet the new Orb",
                bodyKey: "Your floating indicator is now a living, audio-reactive orb. It breathes while idle, swells when you speak, and streams your words live as you dictate.",
                credit: nil
            ),
            AnnouncementItem(
                id: "streaming-transcription",
                visual: .symbol("waveform"),
                titleKey: "Streaming transcription, instantly ready",
                bodyKey: "The new Nemotron streaming engine shows words as you say them, and the engine prewarms at launch so your first dictation starts without a delay.",
                credit: nil
            ),
            AnnouncementItem(
                id: "bluetooth-external-mics",
                visual: .symbol("headphones"),
                titleKey: "Better Bluetooth & external mic support",
                bodyKey: "Recording from external and Bluetooth microphones is now rock solid, even when your audio output is routed elsewhere.",
                credit: AnnouncementCredit(
                    name: "@ntdkhang",
                    url: URL(string: "https://github.com/ntdkhang"),
                    labelKey: "Thanks to %@ for investigating and kicking off the fix (PR #64)."
                )
            ),
            AnnouncementItem(
                id: "russian-ukrainian-dictation",
                visual: .symbol("globe"),
                titleKey: "Dictate in Russian and Ukrainian",
                bodyKey: "Two new dictation languages, fully wired into model recommendations.",
                credit: AnnouncementCredit(
                    name: "@nezzard",
                    url: URL(string: "https://github.com/nezzard"),
                    labelKey: "Thanks to %@ for the contribution (PR #61)."
                )
            ),
        ]
    )
}
