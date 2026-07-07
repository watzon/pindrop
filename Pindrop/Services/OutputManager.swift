//
//  OutputManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AppKit
import ApplicationServices
import os.log

enum OutputMode {
    case clipboard
    case directInsert
}

enum OutputManagerError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case emptyText
    case clipboardWriteFailed
    case textInsertionFailed
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for direct text insertion"
        case .emptyText:
            return "Cannot output empty text"
        case .clipboardWriteFailed:
            return "Failed to write text to clipboard"
        case .textInsertionFailed:
            return "Failed to insert text directly"
        }
    }
}

// MARK: - Protocols

protocol ClipboardProtocol {
    func copyToClipboard(_ text: String) -> Bool
    func captureSnapshot() -> ClipboardSnapshot
    func currentChangeCount() -> Int
    func currentStringContent() -> String?
    func restoreSnapshot(_ snapshot: ClipboardSnapshot) -> Bool
}

struct ClipboardSnapshot {
    let items: [[String: Data]]
    let changeCount: Int

    static let empty = ClipboardSnapshot(items: [], changeCount: 0)
}

protocol KeySimulationProtocol {
    func simulatePaste() async throws
}

struct KeySimulationEvent: Equatable {
    let virtualKey: CGKeyCode
    let keyDown: Bool
    let flags: CGEventFlags
}

// MARK: - Real Implementations

final class SystemClipboard: ClipboardProtocol {
    func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func captureSnapshot() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            return .empty
        }

        let items = pasteboardItems.map { item in
            var capturedItem: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    capturedItem[type.rawValue] = data
                }
            }
            return capturedItem
        }

        return ClipboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    func currentChangeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    func currentStringContent() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func restoreSnapshot(_ snapshot: ClipboardSnapshot) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else {
            return true
        }

        let pasteboardItems = snapshot.items.map { capturedItem in
            let item = NSPasteboardItem()
            for (type, data) in capturedItem {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }

        return pasteboard.writeObjects(pasteboardItems)
    }
}

final class SystemKeySimulation: KeySimulationProtocol {
    private let pasteScriptRunner: () throws -> Bool
    private let keyEventPoster: (CGEventSource?, KeySimulationEvent) -> Bool
    private let sleeper: (UInt64) async throws -> Void

    init(
        pasteScriptRunner: @escaping () throws -> Bool = SystemKeySimulation.runSystemEventsPasteScript,
        keyEventPoster: @escaping (CGEventSource?, KeySimulationEvent) -> Bool = SystemKeySimulation.postKeyEvent,
        sleeper: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.pasteScriptRunner = pasteScriptRunner
        self.keyEventPoster = keyEventPoster
        self.sleeper = sleeper
    }

    func simulatePaste() async throws {
        do {
            try await simulatePasteWithCGEvent()
            return
        } catch {
            Log.output.debug("CGEvent paste failed; falling back to System Events: \(error.localizedDescription)")
            if try pasteScriptRunner() {
                return
            }

            throw error
        }
    }

    private static func runSystemEventsPasteScript() throws -> Bool {
        let scriptSource = "tell application \"System Events\" to keystroke \"v\" using command down"
        guard let script = NSAppleScript(source: scriptSource) else {
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error {
            Log.output.debug("System Events paste failed: \(String(describing: error))")
            return false
        }

        return true
    }

    private func simulatePasteWithCGEvent() async throws {
        let commandKeyCode: CGKeyCode = 0x37
        let vKeyCode: CGKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)

        let events = [
            KeySimulationEvent(virtualKey: commandKeyCode, keyDown: true, flags: .maskCommand),
            KeySimulationEvent(virtualKey: vKeyCode, keyDown: true, flags: .maskCommand),
            KeySimulationEvent(virtualKey: vKeyCode, keyDown: false, flags: .maskCommand),
            KeySimulationEvent(virtualKey: commandKeyCode, keyDown: false, flags: []),
        ]

        for (index, event) in events.enumerated() {
            guard keyEventPoster(source, event) else {
                Log.output.error("Failed to create CGEvent for paste")
                throw OutputManagerError.textInsertionFailed
            }

            if index < events.endIndex - 1 {
                try await sleeper(50_000_000)
            }
        }
    }

    private static func postKeyEvent(source: CGEventSource?, event: KeySimulationEvent) -> Bool {
        guard let cgEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: event.virtualKey,
            keyDown: event.keyDown
        ) else {
            Log.output.error("Failed to create CGEvents for paste")
            return false
        }

        cgEvent.flags = event.flags
        cgEvent.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor
final class OutputManager {

    /// How `output(_:)` actually landed the text in the target app. `.pasted` means the
    /// paste keystroke was issued; `.copiedToClipboard` means insertion wasn't possible
    /// (no accessibility permission, or the paste failed) and the text was left on the
    /// clipboard for the user to paste manually — callers can surface that distinction.
    enum OutputResult: Equatable {
        case pasted
        case copiedToClipboard
    }

    private(set) var outputMode: OutputMode
    private let clipboard: ClipboardProtocol
    private let keySimulation: KeySimulationProtocol
    private let accessibilityPermissionChecker: () -> Bool
    private let frontmostApplicationProvider: () -> NSRunningApplication?

    init(
        outputMode: OutputMode = .clipboard,
        clipboard: ClipboardProtocol = SystemClipboard(),
        keySimulation: KeySimulationProtocol = SystemKeySimulation(),
        accessibilityPermissionChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        frontmostApplicationProvider: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    ) {
        self.outputMode = outputMode
        self.clipboard = clipboard
        self.keySimulation = keySimulation
        self.accessibilityPermissionChecker = accessibilityPermissionChecker
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }
    
    func setOutputMode(_ mode: OutputMode) {
        self.outputMode = mode
    }
    
    @discardableResult
    func output(_ text: String) async throws -> OutputResult {
        guard !text.isEmpty else {
            throw OutputManagerError.emptyText
        }

        Log.output.debug("Output called, mode: \(String(describing: self.outputMode)), length: \(text.count)")

        switch outputMode {
        case .clipboard:
            return try await outputViaClipboard(text)
        case .directInsert:
            return try await outputViaDirectInsert(text)
        }
    }

    func pasteText(_ text: String) async throws {
        guard !text.isEmpty else {
            throw OutputManagerError.emptyText
        }

        try await pasteViaClipboard(text, restoreClipboard: true)
    }

    private func outputViaClipboard(_ text: String) async throws -> OutputResult {
        guard checkAccessibilityPermission() else {
            try copyToClipboard(text)
            return .copiedToClipboard
        }

        do {
            try await pasteViaClipboard(text, restoreClipboard: true)
            return .pasted
        } catch {
            try copyToClipboard(text)
            return .copiedToClipboard
        }
    }

    /// Direct insert is paste-based: one atomic Cmd+V with clipboard snapshot/restore.
    /// (Character-by-character CGEvent typing was removed — the overlay-streaming
    /// architecture inserts final text exactly once, and paste is the only insertion
    /// primitive reliable across apps.) On paste failure the text is left on the
    /// clipboard so the user's words are never lost.
    private func outputViaDirectInsert(_ text: String) async throws -> OutputResult {
        guard checkAccessibilityPermission() else {
            try copyToClipboard(text)
            return .copiedToClipboard
        }

        do {
            try await pasteViaClipboard(text, restoreClipboard: true)
            return .pasted
        } catch {
            Log.output.error("Direct insert paste failed; leaving text on clipboard: \(error.localizedDescription)")
            try copyToClipboard(text)
            return .copiedToClipboard
        }
    }

    private func pasteViaClipboard(_ text: String, restoreClipboard: Bool) async throws {
        let previousSnapshot = restoreClipboard ? clipboard.captureSnapshot() : .empty
        let targetApplication = frontmostApplicationProvider()
        let success = clipboard.copyToClipboard(text)

        guard success else {
            Log.output.error("Failed to write to clipboard")
            throw OutputManagerError.clipboardWriteFailed
        }

        let temporaryClipboardChangeCount = clipboard.currentChangeCount()

        do {
            try await Task.sleep(nanoseconds: 120_000_000)
            targetApplication?.activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 80_000_000)
            try await keySimulation.simulatePaste()

            if restoreClipboard {
                try await Task.sleep(nanoseconds: 500_000_000)
                if shouldRestoreClipboard(expectedChangeCount: temporaryClipboardChangeCount, insertedText: text) {
                    let restored = clipboard.restoreSnapshot(previousSnapshot)
                    if !restored {
                        Log.output.error("Failed to restore clipboard snapshot")
                    }
                } else {
                    Log.output.info("Skipping clipboard restore because clipboard changed externally")
                }
            }
        } catch {
            if restoreClipboard && shouldRestoreClipboard(expectedChangeCount: temporaryClipboardChangeCount, insertedText: text) {
                let restored = clipboard.restoreSnapshot(previousSnapshot)
                if !restored {
                    Log.output.error("Failed to restore clipboard snapshot after paste failure")
                }
            }

            throw error
        }
    }
    
    func copyToClipboard(_ text: String) throws {
        let success = clipboard.copyToClipboard(text)
        
        guard success else {
            throw OutputManagerError.clipboardWriteFailed
        }
    }
    
    func checkAccessibilityPermission() -> Bool {
        accessibilityPermissionChecker()
    }
    
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func shouldRestoreClipboard(expectedChangeCount: Int, insertedText: String) -> Bool {
        clipboard.currentChangeCount() == expectedChangeCount
            || clipboard.currentStringContent() == insertedText
    }
    
}
