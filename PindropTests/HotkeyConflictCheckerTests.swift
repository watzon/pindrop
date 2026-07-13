//
//  HotkeyConflictCheckerTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import Testing
import Carbon
@testable import Pindrop

@Suite("HotkeyConflictChecker")
struct HotkeyConflictCheckerTests {

    private let space: UInt32 = UInt32(kVK_Space)
    private let slash: UInt32 = 44
    private let option: UInt32 = UInt32(optionKey)
    private let command: UInt32 = UInt32(cmdKey)
    private let shift: UInt32 = UInt32(shiftKey)
    private let control: UInt32 = UInt32(controlKey)

    private var defaultAssignments: [HotkeyAssignment] {
        [
            HotkeyAssignment(slot: .toggleRecording, keyCode: space, modifiers: option),
            HotkeyAssignment(slot: .pushToTalk, keyCode: slash, modifiers: command),
            HotkeyAssignment(slot: .copyLastTranscript, keyCode: 8, modifiers: shift | command),
            HotkeyAssignment(slot: .quickCapturePTT, keyCode: space, modifiers: shift | option),
        ]
    }

    @Test("Self-conflict is not a conflict when re-recording the same slot")
    func selfConflictIsNotAConflict() {
        let status = HotkeyConflictChecker.check(
            keyCode: space,
            modifiers: option,
            slot: .toggleRecording,
            assignments: defaultAssignments
        )

        #expect(status == .noConflict)
    }

    @Test("Cross-slot conflict is detected")
    func crossSlotConflictDetected() {
        let status = HotkeyConflictChecker.check(
            keyCode: space,
            modifiers: option,
            slot: .openLibrary,
            assignments: defaultAssignments
        )

        #expect(status == .pindropConflict(conflictingSlot: .toggleRecording))
    }

    @Test("Cancel Operation conflicts with an existing Pindrop slot")
    func cancelOperationConflictsWithToggle() {
        let status = HotkeyConflictChecker.check(
            keyCode: space,
            modifiers: option,
            slot: .cancelOperation,
            assignments: defaultAssignments
        )

        #expect(status == .pindropConflict(conflictingSlot: .toggleRecording))
    }

    @Test("Cancel Operation self reassignment is clean")
    func cancelOperationSelfReassignmentIsClean() {
        let assignments = defaultAssignments + [
            HotkeyAssignment(slot: .cancelOperation, keyCode: UInt32(kVK_ANSI_Period), modifiers: command)
        ]

        let status = HotkeyConflictChecker.check(
            keyCode: UInt32(kVK_ANSI_Period),
            modifiers: command,
            slot: .cancelOperation,
            assignments: assignments
        )

        #expect(status == .noConflict)
    }

    @Test("System table hit returns soft system warning")
    func systemTableHit() {
        let status = HotkeyConflictChecker.check(
            keyCode: space,
            modifiers: command,
            slot: .openLibrary,
            assignments: defaultAssignments
        )

        #expect(status == .systemShortcut(name: "Spotlight"))
    }

    @Test("Clean combo reports no conflicts")
    func cleanCombo() {
        let status = HotkeyConflictChecker.check(
            keyCode: UInt32(kVK_ANSI_J),
            modifiers: command | option,
            slot: .openLibrary,
            assignments: defaultAssignments
        )

        #expect(status == .noConflict)
    }

    @Test("Pindrop conflict takes precedence over system shortcut")
    func pindropPrecedenceOverSystem() {
        // Assign Spotlight (⌘Space) to push-to-talk, then check open-library with same combo.
        let assignments = [
            HotkeyAssignment(slot: .pushToTalk, keyCode: space, modifiers: command),
        ]

        let status = HotkeyConflictChecker.check(
            keyCode: space,
            modifiers: command,
            slot: .openLibrary,
            assignments: assignments
        )

        #expect(status == .pindropConflict(conflictingSlot: .pushToTalk))
    }

    @Test("Mission Control and screenshot system entries are recognized")
    func additionalSystemShortcuts() {
        let missionControl = HotkeyConflictChecker.check(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: control,
            slot: .openLibrary,
            assignments: []
        )
        let screenshot = HotkeyConflictChecker.check(
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: command | shift,
            slot: .openLibrary,
            assignments: []
        )

        #expect(missionControl == .systemShortcut(name: "Mission Control"))
        #expect(screenshot == .systemShortcut(name: "Screenshot"))
    }

    @Test("Ctrl-Up with real capture modifiers (control|fn) matches Mission Control")
    func controlUpWithFnMaskMatchesMissionControl() {
        // HotkeysSettingsView.carbonModifiersFrom includes kEventKeyModifierFnMask for arrows.
        let capturedModifiers = control | UInt32(kEventKeyModifierFnMask)

        let status = HotkeyConflictChecker.check(
            keyCode: UInt32(kVK_UpArrow),
            modifiers: capturedModifiers,
            slot: .openLibrary,
            assignments: []
        )

        #expect(status == .systemShortcut(name: "Mission Control"))
        #expect(
            HotkeyConflictChecker.normalizeModifiers(
                keyCode: UInt32(kVK_UpArrow),
                modifiers: capturedModifiers
            ) == control
        )
    }

    @Test("Fn-primary key keeps the fn mask during normalization")
    func fnPrimaryKeyKeepsFnMask() {
        let modifiers = UInt32(kEventKeyModifierFnMask)
        #expect(
            HotkeyConflictChecker.normalizeModifiers(
                keyCode: UInt32(kVK_Function),
                modifiers: modifiers
            ) == modifiers
        )
    }
}
