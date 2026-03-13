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
    }

    func updateStreamingInsertion(with text: String) async throws {
        guard streamingSessionActive else {
            throw OutputManagerError.textInsertionFailed
        }

        let commonPrefixLength = longestCommonPrefixLength(lastStreamingText, text)
        let charactersToDelete = lastStreamingText.count - commonPrefixLength
        if charactersToDelete > 0 {
            try await deleteBackward(count: charactersToDelete)
        }

        let suffixToInsert = String(text.dropFirst(commonPrefixLength))
        if !suffixToInsert.isEmpty {
            try await insertStreamingSuffix(suffixToInsert)
        }

        lastStreamingText = text
    }

    func finishStreamingInsertion(finalText: String, appendTrailingSpace: Bool) async throws {
        guard streamingSessionActive else {
            throw OutputManagerError.textInsertionFailed
        }

        var finalOutput = finalText
        if appendTrailingSpace, !finalOutput.isEmpty {
            finalOutput += " "
        }

        try await updateStreamingInsertion(with: finalOutput)
        streamingSessionActive = false
        lastStreamingText = ""
    }

    func cancelStreamingInsertion(removeInsertedText: Bool) async {
        guard streamingSessionActive else {
            lastStreamingText = ""
            return
        }

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

        if supportsDirectTyping(text) {
            try await insertTextDirectly(text)
            return
        }

        try await pasteViaClipboard(text, restoreClipboard: true)
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
        if supportsDirectTyping(text) {
            try await insertTextDirectly(text)
        } else {
            try await pasteViaClipboard(text, restoreClipboard: true)
        }
    }

    private func supportsDirectTyping(_ text: String) -> Bool {
        text.allSatisfy { getKeyCodeForCharacter($0) != nil }
    }

    private func deleteBackward(count: Int) async throws {
        guard count > 0 else { return }
        for _ in 0..<count {
            try keySimulation.postKeyEvent(keyCode: 51, flags: [], keyDown: true)
            try await Task.sleep(nanoseconds: 1_000_000)
            try keySimulation.postKeyEvent(keyCode: 51, flags: [], keyDown: false)
        }
    }

    private func longestCommonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var length = 0
        for (left, right) in zip(lhs, rhs) where left == right {
            length += 1
        }
        return length
    }
    
    private func typeCharacter(_ character: Character) async throws {
        guard let (keyCode, modifiers) = getKeyCodeForCharacter(character) else {
            throw OutputManagerError.textInsertionFailed
        }
        
        try keySimulation.postKeyEvent(keyCode: keyCode, flags: modifiers, keyDown: true)
        try await Task.sleep(nanoseconds: 1_000_000)
        try keySimulation.postKeyEvent(keyCode: keyCode, flags: modifiers, keyDown: false)
    }
    
    func getKeyCodeForCharacter(_ character: Character) -> (CGKeyCode, CGEventFlags)? {
        // Basic ASCII character mapping
        // This is a simplified version - a production implementation would need more complete mapping
        
        let keyCodeMap: [Character: (CGKeyCode, CGEventFlags)] = [
            // Lowercase letters
            "a": (0, []), "b": (11, []), "c": (8, []), "d": (2, []), "e": (14, []),
            "f": (3, []), "g": (5, []), "h": (4, []), "i": (34, []), "j": (38, []),
            "k": (40, []), "l": (37, []), "m": (46, []), "n": (45, []), "o": (31, []),
            "p": (35, []), "q": (12, []), "r": (15, []), "s": (1, []), "t": (17, []),
            "u": (32, []), "v": (9, []), "w": (13, []), "x": (7, []), "y": (16, []),
            "z": (6, []),
            
            // Uppercase letters (with shift)
            "A": (0, .maskShift), "B": (11, .maskShift), "C": (8, .maskShift),
            "D": (2, .maskShift), "E": (14, .maskShift), "F": (3, .maskShift),
            "G": (5, .maskShift), "H": (4, .maskShift), "I": (34, .maskShift),
            "J": (38, .maskShift), "K": (40, .maskShift), "L": (37, .maskShift),
            "M": (46, .maskShift), "N": (45, .maskShift), "O": (31, .maskShift),
            "P": (35, .maskShift), "Q": (12, .maskShift), "R": (15, .maskShift),
            "S": (1, .maskShift), "T": (17, .maskShift), "U": (32, .maskShift),
            "V": (9, .maskShift), "W": (13, .maskShift), "X": (7, .maskShift),
            "Y": (16, .maskShift), "Z": (6, .maskShift),
            
            // Numbers
            "0": (29, []), "1": (18, []), "2": (19, []), "3": (20, []), "4": (21, []),
            "5": (23, []), "6": (22, []), "7": (26, []), "8": (28, []), "9": (25, []),
            
            // Special characters
            " ": (49, []), // Space
            ".": (47, []), ",": (43, []), "!": (18, .maskShift), "?": (44, .maskShift),
            ":": (41, .maskShift), ";": (41, []), "'": (39, []), "\"": (39, .maskShift),
            "-": (27, []), "_": (27, .maskShift), "(": (25, .maskShift), ")": (29, .maskShift),
            "\n": (36, []), // Return/Enter
            "\t": (48, []), // Tab
        ]
        
        return keyCodeMap[character]
    }
}
