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

@MainActor
final class OutputManager {
    
    private(set) var outputMode: OutputMode
    
    init(outputMode: OutputMode = .clipboard) {
        self.outputMode = outputMode
    }
    
    // MARK: - Public API
    
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
            try await pasteViaClipboard(text, restoreClipboard: false)
        case .directInsert:
            try await pasteViaClipboard(text, restoreClipboard: true)
        }
    }
    
    // MARK: - Clipboard Operations
    
    private func pasteViaClipboard(_ text: String, restoreClipboard: Bool) async throws {
        let pasteboard = NSPasteboard.general
        
        var previousContents: String? = nil
        if restoreClipboard {
            previousContents = pasteboard.string(forType: .string)
        }
        
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        guard success else {
            Log.output.error("Failed to write to clipboard")
            throw OutputManagerError.clipboardWriteFailed
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        try simulatePaste()
        
        if restoreClipboard, let previous = previousContents {
            try await Task.sleep(nanoseconds: 500_000_000)
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }
    
    private func simulatePaste() throws {
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
        usleep(50000)
        keyUp.post(tap: .cghidEventTap)
    }
    
    func copyToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let success = pasteboard.setString(text, forType: .string)
        
        guard success else {
            throw OutputManagerError.clipboardWriteFailed
        }
    }
    
    // MARK: - Direct Text Insertion
    
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func insertTextDirectly(_ text: String) async throws {
        // Use CGEvent to simulate keyboard input
        // This approach types each character individually
        
        for character in text {
            try await typeCharacter(character)
        }
    }
    
    private func typeCharacter(_ character: Character) async throws {
        // Get the key code and modifiers for this character
        guard let (keyCode, modifiers) = getKeyCodeForCharacter(character) else {
            // If we can't map the character, fall back to clipboard
            throw OutputManagerError.textInsertionFailed
        }
        
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            throw OutputManagerError.textInsertionFailed
        }
        
        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw OutputManagerError.textInsertionFailed
        }
        
        // Apply modifiers if needed
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        // Post events
        keyDownEvent.post(tap: .cgAnnotatedSessionEventTap)
        keyUpEvent.post(tap: .cgAnnotatedSessionEventTap)
        
        // Small delay between characters for reliability
        try await Task.sleep(nanoseconds: 1_000_000) // 1ms
    }
    
    // MARK: - Character to KeyCode Mapping
    
    private func getKeyCodeForCharacter(_ character: Character) -> (CGKeyCode, CGEventFlags)? {
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
