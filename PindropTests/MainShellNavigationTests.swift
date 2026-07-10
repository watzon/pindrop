//
//  MainShellNavigationTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Foundation
import Testing
@testable import Pindrop

@Suite("Main shell navigation (U2)")
struct MainShellNavigationTests {

    @Test func primaryNavigationOrderMatchesViewMenuShortcuts() {
        let expected: [MainNavItem] = [.home, .history, .notes, .dictionary, .models]
        #expect(MainNavItem.primaryNavigationItems == expected)

        #expect(MainNavItem.viewMenuShortcut(for: .home) == "1")
        #expect(MainNavItem.viewMenuShortcut(for: .history) == "2")
        #expect(MainNavItem.viewMenuShortcut(for: .notes) == "3")
        #expect(MainNavItem.viewMenuShortcut(for: .dictionary) == "4")
        #expect(MainNavItem.viewMenuShortcut(for: .models) == "5")
    }

    @Test func transcribeIsNotInPrimaryNavigation() {
        #expect(!MainNavItem.primaryNavigationItems.contains(.transcribe))
        #expect(MainNavItem.viewMenuShortcut(for: .transcribe) == nil)
    }

    @Test func transcribeResolvesToLibrary() {
        #expect(MainNavItem.transcribe.resolvedDestination == .history)
        #expect(MainNavItem.history.resolvedDestination == .history)
        #expect(MainNavItem.home.resolvedDestination == .home)
    }

    @Test func historyTitleKeyIsLibrary() {
        let title = MainNavItem.history.title(locale: Locale(identifier: "en"))
        #expect(title == "Library")
        // rawValue stays History for notification identity stability
        #expect(MainNavItem.history.rawValue == "History")
    }

    @Test func windowTokensMatchScorchedSpec() {
        #expect(AppTheme.Window.mainMinWidth == 980)
        #expect(AppTheme.Window.mainMinHeight == 640)
        #expect(AppTheme.Window.mainDefaultWidth == 1160)
        #expect(AppTheme.Window.mainDefaultHeight == 760)
        #expect(AppTheme.Window.sidebarWidth == 236)
        #expect(AppTheme.Window.sidebarCollapsedWidth == 64)
    }
}

@Suite("Status card phase mapping (U2)")
struct StatusCardPhaseTests {

    @Test func readyWhenIdle() {
        let phase = StatusCardPhase(isRecording: false, isProcessing: false)
        #expect(phase == .ready)
        #expect(phase.isActive == false)
    }

    @Test func recordingTakesPrecedenceOverProcessing() {
        let phase = StatusCardPhase(isRecording: true, isProcessing: true, duration: 12.4)
        #expect(phase == .recording(duration: 12.4))
        #expect(phase.isActive)
    }

    @Test func processingWhenNotRecording() {
        let phase = StatusCardPhase(isRecording: false, isProcessing: true)
        #expect(phase == .processing)
        #expect(phase.isActive)
    }

    @Test func formatDurationRoundsAndPads() {
        #expect(StatusCard.formatDuration(0) == "0:00")
        #expect(StatusCard.formatDuration(5) == "0:05")
        #expect(StatusCard.formatDuration(65.4) == "1:05")
        #expect(StatusCard.formatDuration(65.6) == "1:06")
        #expect(StatusCard.formatDuration(-3) == "0:00")
    }
}
