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
    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) throws
    func postCharacterEvent(character: Character, keyDown: Bool) throws
    func simulatePaste() async throws
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
    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw OutputManagerError.textInsertionFailed
        }
        
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func postCharacterEvent(character: Character, keyDown: Bool) throws {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
            throw OutputManagerError.textInsertionFailed
        }

        var utf16 = Array(String(character).utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        event.post(tap: .cghidEventTap)
    }
    
    func simulatePaste() async throws {
        if try runSystemEventsPasteScript() {
            return
        }

        try await simulatePasteWithCGEvent()
    }

    private func runSystemEventsPasteScript() throws -> Bool {
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
        let vKeyCode: CGKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            Log.output.error("Failed to create CGEvents for paste")
            throw OutputManagerError.textInsertionFailed
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 50_000_000)
        keyUp.post(tap: .cghidEventTap)
    }
}

@MainActor
final class OutputManager {
    
    private(set) var outputMode: OutputMode
    private let clipboard: ClipboardProtocol
    private let keySimulation: KeySimulationProtocol
    private let accessibilityPermissionChecker: () -> Bool
    private let frontmostApplicationProvider: () -> NSRunningApplication?
    private var streamingSessionActive = false
    private var lastStreamingText = ""
    /// Tail of a chain of in-flight streaming writes. Each call to
    /// `updateStreamingInsertion(with:)` or `finishStreamingInsertion(...)` appends a
    /// task that awaits its predecessor before reading `lastStreamingText` and issuing
    /// keystrokes. This prevents concurrent callers from reading a stale baseline and
    /// interleaving their keystrokes. The main actor serializes method entry, but `await`
    /// points inside each write yield the actor, so without this chain a refinement apply
    /// that's still typing can race with the next partial that arrives mid-typing.
    private var streamingWriteChainTail: Task<Void, Error>?
    
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
    
    func output(_ text: String) async throws {
        guard !text.isEmpty else {
            throw OutputManagerError.emptyText
        }
        
        Log.output.debug("Output called, mode: \(String(describing: self.outputMode)), length: \(text.count)")
        
        switch outputMode {
        case .clipboard:
            try await outputViaClipboard(text)
        case .directInsert:
            try await outputViaDirectInsert(text)
        }
    }

    func pasteText(_ text: String) async throws {
        guard !text.isEmpty else {
            throw OutputManagerError.emptyText
        }

        try await pasteViaClipboard(text, restoreClipboard: true)
    }

    func beginStreamingInsertion() {
        streamingSessionActive = true
        lastStreamingText = ""
        streamingWriteChainTail = nil
    }

    func updateStreamingInsertion(with text: String) async throws {
        guard streamingSessionActive else {
            throw OutputManagerError.textInsertionFailed
        }
        try await enqueueStreamingWrite { [weak self] in
            try await self?.performStreamingInsertion(text: text)
        }
    }

    /// Actual diff + keystroke pipeline. Invoked only from inside `enqueueStreamingWrite`
    /// so that `lastStreamingText` and the keystroke stream are consistent with each other
    /// across concurrent callers.
    private func performStreamingInsertion(text: String) async throws {
        guard streamingSessionActive else {
            throw OutputManagerError.textInsertionFailed
        }

        let previous = lastStreamingText
        let commonPrefixLength = longestCommonPrefixLength(previous, text)
        let charactersToDelete = previous.count - commonPrefixLength
        let suffixToInsert = String(text.dropFirst(commonPrefixLength))

        // Compact diagnostics: previous length, target length, prefix match, chars
        // deleted, chars inserted, plus short preview windows around the divergence.
        // Enable with `log stream --predicate 'subsystem == "tech.watzon.pindrop" AND
        // category == "output"' --level=debug`.
        Log.output.debug(
            """
            updateStreamingInsertion diff: \
            prev=\(previous.count) target=\(text.count) \
            prefix=\(commonPrefixLength) delete=\(charactersToDelete) \
            insert=\(suffixToInsert.count) \
            prevTail=\(Self.logWindow(previous, around: commonPrefixLength)) \
            targetTail=\(Self.logWindow(text, around: commonPrefixLength))
            """
        )

        if charactersToDelete > 0 {
            try await deleteBackward(count: charactersToDelete)
        }
        if !suffixToInsert.isEmpty {
            try await insertStreamingSuffix(suffixToInsert)
        }

        lastStreamingText = text
    }

    /// Appends a unit of streaming-write work onto the serial chain. Each enqueued task
    /// awaits its predecessor's completion before running. The chain survives errors —
    /// a throw from one task does not poison the chain, so subsequent writes still run.
    private func enqueueStreamingWrite(
        _ work: @escaping @Sendable () async throws -> Void
    ) async throws {
        let predecessor = streamingWriteChainTail
        let task: Task<Void, Error> = Task { @MainActor in
            _ = try? await predecessor?.value
            try await work()
        }
        streamingWriteChainTail = task
        try await task.value
    }

    /// 30-char window around an index in `text`, with the divergence point marked by `|`,
    /// for debug logs. Never throws — clamps to string bounds.
    private static func logWindow(_ text: String, around index: Int) -> String {
        let count = text.count
        guard count > 0 else { return "<empty>" }
        let clamped = max(0, min(index, count))
        let start = max(0, clamped - 15)
        let end = min(count, clamped + 15)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        let divergeIdx = text.index(text.startIndex, offsetBy: clamped)
        let left = text[startIdx..<divergeIdx]
        let right = text[divergeIdx..<endIdx]
        return "\"\(left)|\(right)\""
    }

    func finishStreamingInsertion(finalText: String, appendTrailingSpace: Bool) async throws {
        guard streamingSessionActive else {
            throw OutputManagerError.textInsertionFailed
        }

        var finalOutput = finalText
        if appendTrailingSpace, !finalOutput.isEmpty {
            finalOutput += " "
        }

        // Route through the serial write chain so the final diff runs only after any
        // in-flight streaming writes complete.
        try await enqueueStreamingWrite { [weak self] in
            try await self?.performStreamingInsertion(text: finalOutput)
        }
        streamingSessionActive = false
        lastStreamingText = ""
        streamingWriteChainTail = nil
    }

    func cancelStreamingInsertion(removeInsertedText: Bool) async {
        guard streamingSessionActive else {
            lastStreamingText = ""
            return
        }

        // Wait for any in-flight writes to drain so we don't interleave our delete with
        // their keystrokes. An error thrown by a prior write is irrelevant here; swallow.
        if let tail = streamingWriteChainTail {
            _ = try? await tail.value
        }
        streamingWriteChainTail = nil

        if removeInsertedText && !lastStreamingText.isEmpty {
            try? await deleteBackward(count: lastStreamingText.count)
        }

        streamingSessionActive = false
        lastStreamingText = ""
    }
    
    private func outputViaClipboard(_ text: String) async throws {
        guard checkAccessibilityPermission() else {
            try copyToClipboard(text)
            return
        }

        do {
            try await pasteViaClipboard(text, restoreClipboard: true)
        } catch {
            try copyToClipboard(text)
        }
    }

    private func outputViaDirectInsert(_ text: String) async throws {
        guard checkAccessibilityPermission() else {
            try copyToClipboard(text)
            return
        }

        try await insertTextDirectly(text)
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
    
    private func insertTextDirectly(_ text: String) async throws {
        for character in text {
            try await typeCharacter(character)
        }
    }

    private func insertStreamingSuffix(_ text: String) async throws {
        try await insertTextDirectly(text)
    }

    private func deleteBackward(count: Int) async throws {
        guard count > 0 else { return }
        for _ in 0..<count {
            try keySimulation.postKeyEvent(keyCode: 51, flags: [], keyDown: true)
            try await Task.sleep(nanoseconds: 1_000_000)
            try keySimulation.postKeyEvent(keyCode: 51, flags: [], keyDown: false)
        }
    }

    /// Length of the longest common PREFIX (measured in Character units) between `lhs` and
    /// `rhs`. Must stop at the first mismatch — without an early break, a `where` filter
    /// would keep counting matching character positions beyond the divergence, which is
    /// wrong for any input with interior edits (e.g. AI-refined streams replacing words
    /// mid-string). Monotone streaming inputs happen to hide this bug because each partial
    /// is a strict extension of the previous, but refinement introduces interior diffs.
    private func longestCommonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (left, right) in zip(lhs, rhs) {
            if left != right { break }
            length += 1
        }
        return length
    }
    
    private func typeCharacter(_ character: Character) async throws {
        try keySimulation.postCharacterEvent(character: character, keyDown: true)
        try await Task.sleep(nanoseconds: 1_000_000)
        try keySimulation.postCharacterEvent(character: character, keyDown: false)
    }
}
