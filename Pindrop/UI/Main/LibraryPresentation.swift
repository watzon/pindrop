//
//  LibraryPresentation.swift
//  Pindrop
//
//  Created on 2026-07-09.
//
//  Pure helpers for Library list presentation (U3). No SwiftUI / SwiftData side effects.
//

import Foundation
import SwiftUI

// MARK: - Filter chips ↔ source kinds

/// Four Library filter chips (spec §4 / U3). Maps onto `HistoryStore.HistoryFilter`
/// and the underlying `MediaSourceKind` sets.
enum LibraryFilterChip: String, CaseIterable, Equatable, Sendable, Identifiable {
    case all
    case dictations
    case meetings
    case media

    var id: String { rawValue }

    /// `nil` means every source kind.
    var sourceKinds: Set<MediaSourceKind>? {
        switch self {
        case .all:
            return nil
        case .dictations:
            return [.voiceRecording]
        case .meetings:
            return [.manualCapture]
        case .media:
            return [.importedFile, .webLink]
        }
    }

    var historyFilter: HistoryStore.HistoryFilter {
        switch self {
        case .all: return .all
        case .dictations: return .voice
        case .meetings: return .meetings
        case .media: return .media
        }
    }

    static func from(historyFilter: HistoryStore.HistoryFilter) -> LibraryFilterChip {
        switch historyFilter {
        case .all: return .all
        case .voice: return .dictations
        case .meetings: return .meetings
        case .media: return .media
        }
    }

    /// Whether a source kind is included by this chip.
    func includes(_ kind: MediaSourceKind) -> Bool {
        guard let sourceKinds else { return true }
        return sourceKinds.contains(kind)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .all:
            return localized("All", locale: locale)
        case .dictations:
            return localized("Dictations", locale: locale)
        case .meetings:
            return localized("Meetings", locale: locale)
        case .media:
            return localized("Media", locale: locale)
        }
    }
}

// MARK: - Day sections

struct LibraryDaySection {
    let key: String
    let records: [TranscriptionRecord]
}

enum LibraryDayGrouping {
    /// Groups records into Today / Yesterday / medium-date sections and orders them
    /// newest-first (or oldest-first when `newestFirst` is false).
    static func sections(
        from records: [TranscriptionRecord],
        calendar: Calendar = .current,
        now: Date = Date(),
        newestFirst: Bool = true,
        dateFormatter: DateFormatter = defaultDayFormatter
    ) -> [LibraryDaySection] {
        let grouped = Dictionary(grouping: records) { record -> String in
            if calendar.isDate(record.timestamp, inSameDayAs: now) {
                return "Today"
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(record.timestamp, inSameDayAs: yesterday) {
                return "Yesterday"
            }
            return dateFormatter.string(from: record.timestamp)
        }

        let order: [String] = ["Today", "Yesterday"]
        return grouped.sorted { a, b in
            let aIndex = order.firstIndex(of: a.key) ?? Int.max
            let bIndex = order.firstIndex(of: b.key) ?? Int.max
            if aIndex != bIndex {
                return newestFirst ? aIndex < bIndex : aIndex > bIndex
            }
            let aDate = a.value.first?.timestamp ?? .distantPast
            let bDate = b.value.first?.timestamp ?? .distantPast
            return newestFirst ? aDate > bDate : aDate < bDate
        }.map { LibraryDaySection(key: $0.key, records: $0.value) }
    }

    static let defaultDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Localized section title for Today/Yesterday keys; other keys pass through.
    static func displayTitle(_ key: String, locale: Locale) -> String {
        switch key {
        case "Today":
            return localized("Today", locale: locale)
        case "Yesterday":
            return localized("Yesterday", locale: locale)
        default:
            return key
        }
    }
}

// MARK: - Header meta

enum LibraryHeaderMeta {
    /// "N recordings · X h Y m spoken" (or singular / no-duration variants).
    static func text(
        recordingCount: Int,
        spokenDuration: TimeInterval,
        locale: Locale
    ) -> String {
        let countPart: String
        if recordingCount == 1 {
            countPart = localized("1 recording", locale: locale)
        } else {
            countPart = String(
                format: localized("%d recordings", locale: locale),
                recordingCount
            )
        }

        let spoken = formatSpokenDuration(spokenDuration, locale: locale)
        guard !spoken.isEmpty else { return countPart }
        return "\(countPart) · \(spoken)"
    }

    /// Formats a duration as "X h Y m spoken" / "Y m spoken" / empty when zero.
    static func formatSpokenDuration(_ duration: TimeInterval, locale: Locale) -> String {
        guard duration.isFinite, duration > 0 else { return "" }
        let totalMinutes = Int(duration.rounded(.down)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return String(
                format: localized("%d h %d m spoken", locale: locale),
                hours,
                minutes
            )
        }
        if hours > 0 {
            return String(
                format: localized("%d h spoken", locale: locale),
                hours
            )
        }
        return String(
            format: localized("%d m spoken", locale: locale),
            max(1, minutes)
        )
    }
}

// MARK: - Retention caption

enum LibraryRetentionCaption {
    /// Policy caption for the expanded player card, e.g. "audio kept 7 days".
    /// Empty when retention is off or the record has no audio to keep.
    static func caption(
        retention: DictationAudioRetention,
        hasAudio: Bool,
        sourceKind: MediaSourceKind,
        locale: Locale
    ) -> String? {
        guard hasAudio, sourceKind == .voiceRecording else { return nil }
        switch retention {
        case .off:
            return nil
        case .days7:
            return localized("audio kept 7 days", locale: locale)
        case .days30:
            return localized("audio kept 30 days", locale: locale)
        case .forever:
            return localized("audio kept forever", locale: locale)
        }
    }
}

// MARK: - Kind presentation

enum LibraryKindPresentation {
    static func badgeTitle(for kind: MediaSourceKind, locale: Locale) -> String {
        switch kind {
        case .voiceRecording:
            return localized("Dictation", locale: locale)
        case .manualCapture:
            return localized("Meeting", locale: locale)
        case .importedFile, .webLink:
            return localized("Media", locale: locale)
        }
    }

    static func systemImage(for kind: MediaSourceKind) -> String {
        switch kind {
        case .voiceRecording:
            return "mic.fill"
        case .manualCapture:
            return "person.2.fill"
        case .importedFile:
            return "headphones"
        case .webLink:
            return "film"
        }
    }

    static func destinationPill(appName: String?) -> String? {
        guard let appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "→ \(appName)"
    }

    static func insertedIntoCaption(appName: String?, locale: Locale) -> String? {
        guard let appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return String(
            format: localized("inserted into %@", locale: locale),
            appName
        )
    }
}

// MARK: - Speaker colors

/// Stable per-speaker palette for meeting transcript turns (spec §8).
enum LibrarySpeakerColor {
    /// Fixed palette (≥6 hues) hashed by speaker id for stable assignment.
    static let palette: [Color] = [
        Color(red: 0.078, green: 0.439, blue: 0.541), // #14708A teal (design)
        Color(red: 0.302, green: 0.478, blue: 0.290), // evergreen
        Color(red: 0.180, green: 0.306, blue: 0.451), // paper blue
        Color(red: 0.941, green: 0.427, blue: 0.310), // signal
        Color(red: 0.122, green: 0.427, blue: 0.325), // library green
        Color(red: 0.949, green: 0.710, blue: 0.290), // pindrop gold
        Color(red: 0.557, green: 0.376, blue: 0.655), // soft violet
        Color(red: 0.851, green: 0.325, blue: 0.510)  // rose
    ]

    /// Canonical color key: prefer non-empty `speakerId`, else non-empty label, else `"_"`.
    /// Use this everywhere a speaker color is resolved so empty-id segments match the footer.
    static func canonicalKey(speakerId: String, speakerLabel: String) -> String {
        let trimmedID = speakerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty { return trimmedID }
        let trimmedLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty { return trimmedLabel }
        return "_"
    }

    static func color(for speakerID: String) -> Color {
        palette[index(for: speakerID)]
    }

    static func color(speakerId: String, speakerLabel: String) -> Color {
        color(for: canonicalKey(speakerId: speakerId, speakerLabel: speakerLabel))
    }

    /// Stable index into `palette` for a given speaker key.
    static func index(for speakerID: String) -> Int {
        let key = speakerID.isEmpty ? "_" : speakerID
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(palette.count))
    }
}

// MARK: - Playback rates

enum LibraryPlaybackRate {
    /// Spec §6 speed chip cycle: 1× → 1.5× → 2× → 1×.
    static let cycle: [Float] = [1.0, 1.5, 2.0]

    static func next(after rate: Float) -> Float {
        if let index = cycle.firstIndex(where: { abs($0 - rate) < 0.01 }) {
            return cycle[(index + 1) % cycle.count]
        }
        return cycle[0]
    }

    static func label(for rate: Float) -> String {
        let rounded = (rate * 100).rounded() / 100
        if abs(rounded - 1.0) < 0.01 { return "1×" }
        if abs(rounded - 1.5) < 0.01 { return "1.5×" }
        if abs(rounded - 2.0) < 0.01 { return "2×" }
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.2g×", rounded)
    }
}
