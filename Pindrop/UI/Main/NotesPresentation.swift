//
//  NotesPresentation.swift
//  Pindrop
//
//  Created on 2026-07-10.
//
//  Pure helpers for Notes page + note editor presentation (U5). No SwiftUI side effects.
//

import Foundation

// MARK: - Header meta

enum NotesHeaderMeta {
    /// "1 note" / "N notes"
    static func text(noteCount: Int, locale: Locale) -> String {
        if noteCount == 1 {
            return localized("1 note", locale: locale)
        }
        // Use the catalog format key ("%lld notes") so plural stays lowercase "notes".
        return String(format: localized("%lld notes", locale: locale), locale: locale, noteCount)
    }
}

// MARK: - Date / relative labels

enum NotesDateFormatting {
    /// Compact relative label for pinned cards, e.g. "edited just now", "edited 2 h ago".
    static func editedLabel(
        date: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        let relative = compactRelative(from: date, now: now, locale: locale)
        return String(
            format: localized("edited %@", locale: locale),
            relative
        )
    }

    /// Note-row date lane (88 pt): time today, weekday yesterday, else medium date.
    static func rowDate(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter(locale: locale).string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return localized("Yesterday", locale: locale)
        }
        return mediumDateFormatter(locale: locale).string(from: date)
    }

    /// Footer-style "edited just now" without the "edited" prefix when used alone.
    static func compactRelative(
        from date: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en")
    ) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 45 {
            return localized("just now", locale: locale)
        }
        if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return String(format: localized("%d m ago", locale: locale), minutes)
        }
        if interval < 86_400 {
            let hours = max(1, Int(interval / 3600))
            return String(format: localized("%d h ago", locale: locale), hours)
        }
        let days = max(1, Int(interval / 86_400))
        if days < 7 {
            return String(format: localized("%d d ago", locale: locale), days)
        }
        return mediumDateFormatter(locale: locale).string(from: date)
    }

    // MARK: Formatters

    private static func timeFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private static func mediumDateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Note list content helpers

enum NotesListPresentation {
    static func displayTitle(title: String, content: String, emptyTitle: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.isEmpty { return emptyTitle }
        if preview.count > 80 { return String(preview.prefix(80)) + "…" }
        return preview
    }

    /// One-line body preview with whitespace collapsed.
    static func previewLine(content: String, empty: String = "") -> String {
        let collapsed = content
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? empty : collapsed
    }
}
