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
        id: "2026.07-v1.22",
        titleKey: "What's new",
        headerKey: "Pindrop 1.22.0 · July 2026",
        subtitleKey: "Private diagnostics, editable history, deeper performance insights, and more reliable dictation.",
        footerKey: "Also: prompt presets are back in the menu bar, the recording orb has a new waveform, and existing libraries open reliably again.",
        items: [
            AnnouncementItem(
                id: "reliability",
                visual: .symbol("bolt.shield"),
                titleKey: "More reliable dictation",
                bodyKey: "Streaming callbacks, shutdown, and live UI updates now stay ordered and efficient.",
                credit: nil
            ),
            AnnouncementItem(
                id: "privacy",
                visual: .symbol("hand.raised"),
                titleKey: "Privacy-first diagnostics",
                bodyKey: "Telemetry stays off until you opt in, and training contributions remain on your Mac for review, export, or deletion.",
                credit: nil
            ),
            AnnouncementItem(
                id: "editing",
                visual: .symbol("pencil"),
                titleKey: "Editable transcripts",
                bodyKey: "Correct saved transcripts in Library and keep a clear Edited marker.",
                credit: nil
            ),
            AnnouncementItem(
                id: "insights",
                visual: .symbol("chart.bar.xaxis"),
                titleKey: "Pipeline insights",
                bodyKey: "See per-stage timing and AI token usage for each dictation, plus averages in Stats.",
                credit: nil
            ),
        ]
    )
}
