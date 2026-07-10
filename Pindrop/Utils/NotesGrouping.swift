//
//  NotesGrouping.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation

/// Pure helpers for Notes page list grouping: pinned first, then date sections.
enum NotesGrouping {
    /// Stable section keys used by the Notes list (UI localizes display titles).
    enum SectionKey: Hashable, Sendable {
        case pinned
        case today
        case yesterday
        /// Calendar day start used for older sections (sorted newest-first).
        case day(Date)

        /// English fallback titles used in tests and as localization keys.
        var localizationKey: String {
            switch self {
            case .pinned: return "Pinned"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .day(let date):
                return NotesGrouping.dayFormatter.string(from: date)
            }
        }
    }

    struct Input: Equatable, Sendable {
        let id: UUID
        let updatedAt: Date
        let isPinned: Bool
    }

    struct Section: Equatable, Sendable {
        let key: SectionKey
        let ids: [UUID]
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Groups notes with pinned items first (newest-first within the section),
    /// then unpinned notes by Today / Yesterday / earlier calendar day.
    static func sections(
        notes: [Input],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Section] {
        let pinned = notes
            .filter(\.isPinned)
            .sorted { $0.updatedAt > $1.updatedAt }

        let unpinned = notes
            .filter { !$0.isPinned }
            .sorted { $0.updatedAt > $1.updatedAt }

        var result: [Section] = []
        if !pinned.isEmpty {
            result.append(Section(key: .pinned, ids: pinned.map(\.id)))
        }

        let grouped = Dictionary(grouping: unpinned) { note -> SectionKey in
            dateSectionKey(for: note.updatedAt, now: now, calendar: calendar)
        }

        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            sectionSortOrder(lhs, now: now, calendar: calendar)
                < sectionSortOrder(rhs, now: now, calendar: calendar)
        }

        for key in orderedKeys {
            guard let items = grouped[key], !items.isEmpty else { continue }
            let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
            result.append(Section(key: key, ids: sorted.map(\.id)))
        }

        return result
    }

    /// Convenience for views that already hold model objects with UUID ids.
    static func dateSectionKey(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SectionKey {
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        let dayStart = calendar.startOfDay(for: date)
        return .day(dayStart)
    }

    private static func sectionSortOrder(
        _ key: SectionKey,
        now: Date,
        calendar: Calendar
    ) -> (Int, TimeInterval) {
        switch key {
        case .pinned:
            return (0, 0)
        case .today:
            return (1, 0)
        case .yesterday:
            return (2, 0)
        case .day(let date):
            // Newer days first among "earlier" sections.
            let interval = calendar.startOfDay(for: now).timeIntervalSince(date)
            return (3, interval)
        }
    }
}
