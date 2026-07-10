//
//  HotkeyConflictChecker.swift
//  Pindrop
//
//  Created on 2026-07-09.
//

import Foundation
import Carbon

/// Identifies a configurable global hotkey slot in Settings.
enum HotkeySlot: String, CaseIterable, Equatable, Sendable {
    case toggleRecording
    case pushToTalk
    case copyLastTranscript
    case quickCapturePTT
    case quickCaptureToggle
    case openLibrary

    /// English display name used by `localized(...)` keys.
    var displayName: String {
        switch self {
        case .toggleRecording:
            return "Toggle Recording"
        case .pushToTalk:
            return "Push-to-Talk"
        case .copyLastTranscript:
            return "Copy Last Transcript"
        case .quickCapturePTT:
            return "Note Capture — Hold"
        case .quickCaptureToggle:
            return "Note Capture — Toggle"
        case .openLibrary:
            return "Open Library"
        }
    }

    /// Identifier used by `HotkeyManager` / registration.
    var registrationIdentifier: String {
        switch self {
        case .toggleRecording:
            return "toggle-recording"
        case .pushToTalk:
            return "push-to-talk"
        case .copyLastTranscript:
            return "copy-last-transcript"
        case .quickCapturePTT:
            return "quick-capture-ptt"
        case .quickCaptureToggle:
            return "quick-capture-toggle"
        case .openLibrary:
            return "open-library"
        }
    }
}

/// A currently assigned (or candidate) hotkey binding for conflict checks.
struct HotkeyAssignment: Equatable, Sendable {
    let slot: HotkeySlot
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Result of checking a candidate combo against existing assignments and a static system table.
enum HotkeyConflictStatus: Equatable, Sendable {
    /// No Pindrop or known system conflict.
    case noConflict
    /// Same combo is already used by another Pindrop slot.
    case pindropConflict(conflictingSlot: HotkeySlot)
    /// Combo matches a curated known macOS system shortcut (best-effort).
    case systemShortcut(name: String)
}

/// Pure conflict checking for hotkey capture UI and unit tests.
enum HotkeyConflictChecker {
    struct SystemShortcut: Equatable, Sendable {
        let keyCode: UInt32
        let modifiers: UInt32
        let name: String
    }

    /// Curated common macOS shortcuts. Cannot enumerate third-party bindings.
    static let systemShortcuts: [SystemShortcut] = [
        SystemShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), name: "Spotlight"),
        SystemShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey), name: "Finder search"),
        SystemShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), name: "Input source"),
        SystemShortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey), name: "App switcher"),
        SystemShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey), name: "Mission Control"),
        SystemShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey), name: "Mission Control"),
        SystemShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), name: "Screenshot"),
        SystemShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), name: "Screenshot"),
        SystemShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey), name: "Screenshot"),
        SystemShortcut(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey), name: "Window cycle"),
    ]

    /// Checks a candidate combo for the given slot.
    ///
    /// - Self-conflict is not a conflict: re-recording the same slot with its current combo is clean.
    /// - Pindrop-internal conflicts take precedence over system-shortcut soft warnings.
    static func check(
        keyCode: UInt32,
        modifiers: UInt32,
        slot: HotkeySlot,
        assignments: [HotkeyAssignment]
    ) -> HotkeyConflictStatus {
        for assignment in assignments {
            guard assignment.slot != slot else { continue }
            if assignment.keyCode == keyCode && assignment.modifiers == modifiers {
                return .pindropConflict(conflictingSlot: assignment.slot)
            }
        }

        for system in systemShortcuts {
            if system.keyCode == keyCode && system.modifiers == modifiers {
                return .systemShortcut(name: system.name)
            }
        }

        return .noConflict
    }
}
