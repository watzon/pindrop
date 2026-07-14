//
//  NotesPresentationTests.swift
//  PindropTests
//
//  Created on 2026-07-10.
//

import Foundation
import Testing
@testable import Pindrop

@Suite
struct NotesPresentationTests {

    private let en = Locale(identifier: "en")
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    // MARK: - Header meta

    @Test func headerMetaSingularAndPlural() {
        #expect(NotesHeaderMeta.text(noteCount: 1, locale: en) == "1 note")
        #expect(NotesHeaderMeta.text(noteCount: 0, locale: en) == "0 notes")
        #expect(NotesHeaderMeta.text(noteCount: 24, locale: en) == "24 notes")
    }

    // MARK: - Row date formatting

    @Test func rowDateUsesTimeForToday() {
        let now = date(year: 2026, month: 7, day: 10, hour: 15, minute: 30)
        let sameDay = date(year: 2026, month: 7, day: 10, hour: 9, minute: 5)
        let label = NotesDateFormatting.rowDate(
            date: sameDay,
            now: now,
            calendar: calendar,
            locale: en
        )
        // Short time — contains hour digits; locale-dependent am/pm.
        #expect(!label.isEmpty)
        #expect(!label.localizedCaseInsensitiveContains("July"))
    }

    @Test func rowDateUsesYesterdayLabel() {
        let now = date(year: 2026, month: 7, day: 10, hour: 12)
        let yesterday = date(year: 2026, month: 7, day: 9, hour: 18)
        let label = NotesDateFormatting.rowDate(
            date: yesterday,
            now: now,
            calendar: calendar,
            locale: en
        )
        #expect(label == "Yesterday")
    }

    @Test func rowDateUsesMediumDateForOlder() {
        let now = date(year: 2026, month: 7, day: 10, hour: 12)
        let older = date(year: 2026, month: 5, day: 1, hour: 10)
        let label = NotesDateFormatting.rowDate(
            date: older,
            now: now,
            calendar: calendar,
            locale: en
        )
        #expect(label.contains("2026") || label.contains("May") || label.contains("5"))
    }

    // MARK: - Relative / edited labels

    @Test func compactRelativeJustNow() {
        let now = date(year: 2026, month: 7, day: 10, hour: 12)
        let recent = now.addingTimeInterval(-10)
        #expect(
            NotesDateFormatting.compactRelative(from: recent, now: now, locale: en)
                == "just now"
        )
    }

    @Test func compactRelativeMinutesAndHours() {
        let now = date(year: 2026, month: 7, day: 10, hour: 12)
        #expect(
            NotesDateFormatting.compactRelative(
                from: now.addingTimeInterval(-120),
                now: now,
                locale: en
            ) == "2 m ago"
        )
        #expect(
            NotesDateFormatting.compactRelative(
                from: now.addingTimeInterval(-7200),
                now: now,
                locale: en
            ) == "2 h ago"
        )
    }

    @Test func editedLabelPrefixesRelative() {
        let now = date(year: 2026, month: 7, day: 10, hour: 12)
        let label = NotesDateFormatting.editedLabel(
            date: now.addingTimeInterval(-30),
            now: now,
            locale: en
        )
        #expect(label == "edited just now")
    }

    // MARK: - List presentation

    @Test func displayTitleFallsBackToContentThenEmpty() {
        #expect(
            NotesListPresentation.displayTitle(title: "  Hello  ", content: "body", emptyTitle: "Untitled")
                == "Hello"
        )
        #expect(
            NotesListPresentation.displayTitle(title: "  ", content: "body text", emptyTitle: "Untitled")
                == "body text"
        )
        #expect(
            NotesListPresentation.displayTitle(title: "", content: "", emptyTitle: "Untitled")
                == "Untitled"
        )
    }

    @Test func previewLineCollapsesWhitespace() {
        #expect(
            NotesListPresentation.previewLine(content: "  hello\n\nworld  ")
                == "hello world"
        )
        #expect(NotesListPresentation.previewLine(content: "   ") == "")
    }

    // MARK: - Search draft intent (empty-state boundary)

    @Test func draftSearchIntentIgnoresWhitespaceOnly() {
        #expect(NotesSearchPresentation.hasDraftSearchIntent("") == false)
        #expect(NotesSearchPresentation.hasDraftSearchIntent("   \n\t  ") == false)
        #expect(NotesSearchPresentation.hasDraftSearchIntent("a") == true)
        #expect(NotesSearchPresentation.hasDraftSearchIntent("  note  ") == true)
    }

    @Test func draftSearchIntentTransitionPublishesOnlyBoundaryCrossings() {
        #expect(
            NotesSearchPresentation.draftSearchIntentTransition(
                previousHasIntent: false,
                draft: "a"
            ) == true
        )
        #expect(
            NotesSearchPresentation.draftSearchIntentTransition(
                previousHasIntent: true,
                draft: "ab"
            ) == nil
        )
        #expect(
            NotesSearchPresentation.draftSearchIntentTransition(
                previousHasIntent: true,
                draft: "   "
            ) == false
        )
        #expect(
            NotesSearchPresentation.draftSearchIntentTransition(
                previousHasIntent: false,
                draft: ""
            ) == nil
        )
        #expect(
            NotesSearchPresentation.draftSearchIntentTransition(
                previousHasIntent: false,
                draft: "  "
            ) == nil
        )
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }
}

@MainActor
@Suite
struct NoteEditorWindowControllerRegistryTests {
    @Test func retainsControllersUntilTheirWindowLifecycleReleasesThem() {
        let registry = NoteEditorWindowControllerRegistry()
        let controller = NoteEditorWindowController()

        registry.retain(controller)
        #expect(registry.count == 1)

        registry.release(controller)
        #expect(registry.count == 0)
    }
}

@Suite
struct SettingsPresentationSnapshotTests {
    @Test func presentationChangesAreLimitedToDockAndLocaleValues() {
        let previous = SettingsPresentationSnapshot(showInDock: false, appLocale: .automatic)
        #expect(previous.changes(from: previous) == (false, false))

        let dockChanges = SettingsPresentationSnapshot(showInDock: true, appLocale: .automatic)
            .changes(from: previous)
        #expect(dockChanges == (true, false))

        let localeChanges = SettingsPresentationSnapshot(showInDock: false, appLocale: .german)
            .changes(from: previous)
        #expect(localeChanges == (false, true))
    }
}

@Suite
struct HistoryLoadRequestTests {
    @Test func rejectsDelayedResultsForSupersededQueryOrFilter() {
        let initial = HistoryLoadRequest(
            query: "first",
            filter: .all,
            sort: .newest
        )
        let changedQuery = HistoryLoadRequest(
            query: "second",
            filter: .all,
            sort: .newest
        )
        let changedFilter = HistoryLoadRequest(
            query: "second",
            filter: .media,
            sort: .newest
        )

        #expect(!HistoryLoadRequest.isCurrent(
            initial,
            generation: 1,
            activeRequest: changedQuery,
            activeGeneration: 2
        ))
        #expect(!HistoryLoadRequest.isCurrent(
            changedQuery,
            generation: 2,
            activeRequest: changedFilter,
            activeGeneration: 3
        ))
        #expect(HistoryLoadRequest.isCurrent(
            changedFilter,
            generation: 3,
            activeRequest: changedFilter,
            activeGeneration: 3
        ))
    }
}
