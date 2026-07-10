//
//  HotkeysSettingsView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import SwiftUI
import AppKit
import Carbon

struct HotkeysSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.locale) private var locale
    @State private var recordingSlot: HotkeySlot?
    @State private var keyMonitor: Any?
    @State private var pendingHotkeyCapture: PendingHotkeyCapture?
    @State private var activeModifierKeyCodes = Set<UInt16>()

    private struct PendingHotkeyCapture {
        let hotkeyString: String
        let keyCode: UInt16
        let modifiers: UInt32
        let isModifierOnly: Bool
    }

    var body: some View {
        Form {
            Section(localized("Dictation", locale: locale)) {
                hotkeySettingRow(
                    slot: .toggleRecording,
                    title: localized("Toggle Recording", locale: locale),
                    detail: localized("Press once to start recording, then press again to stop and transcribe.", locale: locale),
                    hotkey: settings.toggleHotkey,
                    onClear: { settings.updateToggleHotkey("", keyCode: 0, modifiers: 0) }
                )

                hotkeySettingRow(
                    slot: .pushToTalk,
                    title: localized("Push-to-Talk", locale: locale),
                    detail: localized("Hold the shortcut to record, then release to transcribe.", locale: locale),
                    hotkey: settings.pushToTalkHotkey,
                    onClear: { settings.updatePushToTalkHotkey("", keyCode: 0, modifiers: 0) }
                )

                hotkeySettingRow(
                    slot: .copyLastTranscript,
                    title: localized("Copy Last Transcript", locale: locale),
                    detail: localized("Copy the most recent transcript to the clipboard.", locale: locale),
                    hotkey: settings.copyLastTranscriptHotkey,
                    onClear: { settings.updateCopyLastTranscriptHotkey("", keyCode: 0, modifiers: 0) }
                )
            }

            Section(localized("Notes", locale: locale)) {
                hotkeySettingRow(
                    slot: .quickCapturePTT,
                    title: localized("Note Capture — Hold", locale: locale),
                    detail: localized("Hold to record, then release to open the note editor with the transcription.", locale: locale),
                    hotkey: settings.quickCapturePTTHotkey,
                    onClear: { settings.updateQuickCapturePTTHotkey("", keyCode: 0, modifiers: 0) }
                )

                hotkeySettingRow(
                    slot: .quickCaptureToggle,
                    title: localized("Note Capture — Toggle", locale: locale),
                    detail: localized("Press once to start recording, then again to open the note editor.", locale: locale),
                    hotkey: settings.quickCaptureToggleHotkey,
                    onClear: { settings.updateQuickCaptureToggleHotkey("", keyCode: 0, modifiers: 0) }
                )
            }

            Section(localized("Library", locale: locale)) {
                hotkeySettingRow(
                    slot: .openLibrary,
                    title: localized("Open Library", locale: locale),
                    detail: localized("Show the main window and open the Library.", locale: locale),
                    hotkey: settings.openLibraryHotkey,
                    onClear: { settings.updateOpenLibraryHotkey("", keyCode: 0, modifiers: 0) }
                )
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            stopRecording()
        }
    }

    private func hotkeySettingRow(
        slot: HotkeySlot,
        title: String,
        detail: String,
        hotkey: String,
        onClear: @escaping () -> Void
    ) -> some View {
        let isRecording = recordingSlot == slot
        let conflictStatus = liveConflictStatus(for: slot)

        return LabeledContent {
            HotkeyRecorderRow(
                hotkey: hotkey,
                isRecording: isRecording,
                onRecord: { startRecording(for: slot) },
                onClear: onClear
            )
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isRecording, let conflictStatus {
                    HotkeyConflictStatusView(status: conflictStatus, locale: locale)
                }
            }
        }
    }

    private func liveConflictStatus(for slot: HotkeySlot) -> HotkeyConflictStatus? {
        guard recordingSlot == slot, let capture = pendingHotkeyCapture else {
            return nil
        }
        return HotkeyConflictChecker.check(
            keyCode: UInt32(capture.keyCode),
            modifiers: capture.modifiers,
            slot: slot,
            assignments: settings.configuredHotkeyAssignments()
        )
    }

    private func startRecording(for slot: HotkeySlot) {
        stopRecording()
        recordingSlot = slot
        HotkeyManager.setHotkeyCaptureInProgress(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            if event.type == .flagsChanged {
                guard self.isModifierKeyCode(event.keyCode) else {
                    return nil
                }
                if self.modifierKeyIsDown(event) {
                    self.activeModifierKeyCodes.insert(event.keyCode)
                    guard self.isAllowedSoloModifierKeyCode(event.keyCode) else {
                        return nil
                    }

                    let hotkeyString = self.buildHotkeyString(from: event)
                    let carbonModifiers = self.carbonModifiersFrom(event.modifierFlags)
                    self.pendingHotkeyCapture = PendingHotkeyCapture(
                        hotkeyString: hotkeyString,
                        keyCode: event.keyCode,
                        modifiers: carbonModifiers,
                        isModifierOnly: true
                    )

                    return nil
                }

                self.activeModifierKeyCodes.remove(event.keyCode)
                if self.activeModifierKeyCodes.isEmpty,
                   let capture = self.pendingHotkeyCapture,
                   capture.isModifierOnly {
                    self.applyCapturedHotkey(capture, for: slot)
                    self.stopRecording()
                }

                return nil
            }
            if event.type == .keyDown {
                guard !self.isModifierKeyCode(event.keyCode) else {
                    return nil
                }

                let carbonModifiers = self.carbonModifiersFrom(event.modifierFlags)
                let hasModifiers = carbonModifiers != 0
                let isFunctionKey = self.isFunctionKeyCode(event.keyCode)
                guard hasModifiers || isFunctionKey else {
                    return nil
                }

                let hotkeyString = self.buildHotkeyString(from: event)
                self.pendingHotkeyCapture = PendingHotkeyCapture(
                    hotkeyString: hotkeyString,
                    keyCode: event.keyCode,
                    modifiers: carbonModifiers,
                    isModifierOnly: false
                )
                return nil
            }
            if event.type == .keyUp,
               let capture = self.pendingHotkeyCapture,
               !capture.isModifierOnly,
               capture.keyCode == event.keyCode {
                self.applyCapturedHotkey(capture, for: slot)
                self.stopRecording()
                return nil
            }

            return nil
        }
    }

    private func applyCapturedHotkey(_ capture: PendingHotkeyCapture, for slot: HotkeySlot) {
        let hotkey = capture.hotkeyString
        let keyCode = Int(capture.keyCode)
        let modifiers = Int(capture.modifiers)

        switch slot {
        case .toggleRecording:
            settings.updateToggleHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        case .pushToTalk:
            settings.updatePushToTalkHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        case .copyLastTranscript:
            settings.updateCopyLastTranscriptHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        case .quickCapturePTT:
            settings.updateQuickCapturePTTHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        case .quickCaptureToggle:
            settings.updateQuickCaptureToggleHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        case .openLibrary:
            settings.updateOpenLibraryHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func isAllowedSoloModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 60, 58, 61, 59, 62, UInt16(kVK_Function):
            return true
        default:
            return false
        }
    }

    private func isFunctionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCodeToName(keyCode).hasPrefix("F")
    }

    private func carbonModifiersFrom(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.function) { carbon |= UInt32(kEventKeyModifierFnMask) }
        return carbon
    }

    private func stopRecording() {
        HotkeyManager.setHotkeyCaptureInProgress(false)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        pendingHotkeyCapture = nil
        activeModifierKeyCodes.removeAll()
        recordingSlot = nil
    }

    private func buildHotkeyString(from event: NSEvent) -> String {
        var parts: [String] = []

        // Handle left/right modifiers by keyCode
        let keyCode = event.keyCode
        if keyCode == 59 { parts.append("⌃L") }      // Left Control
        else if keyCode == 62 { parts.append("⌃R") } // Right Control
        else if keyCode == 58 { parts.append("⌥L") } // Left Option
        else if keyCode == 61 { parts.append("⌥R") } // Right Option
        else if keyCode == 56 { parts.append("⇧L") } // Left Shift
        else if keyCode == 60 { parts.append("⇧R") } // Right Shift
        else if keyCode == 55 { parts.append("⌘L") } // Left Command
        else if keyCode == 54 { parts.append("⌘R") } // Right Command
        else if keyCode == UInt16(kVK_Function) { parts.append("fn") }
        else {
            // Regular modifiers (for non-modifier keys)
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.command) { parts.append("⌘") }
            if modifiers.contains(.function) { parts.append("fn") }

            // Add the key character
            if let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty {
                let char = characters.first!
                if char.isLetter || char.isNumber {
                    parts.append(String(char))
                } else {
                    let keyName = keyCodeToName(event.keyCode)
                    if !keyName.isEmpty {
                        parts.append(keyName)
                    }
                }
            } else {
                let keyName = keyCodeToName(event.keyCode)
                if !keyName.isEmpty {
                    parts.append(keyName)
                }
            }
        }

        return parts.joined()
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 60, 58, 61, 59, 62, UInt16(kVK_Function):
            return true
        default:
            return false
        }
    }

    private func modifierKeyIsDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 54, 55:
            return event.modifierFlags.contains(.command)
        case 58, 61:
            return event.modifierFlags.contains(.option)
        case 56, 60:
            return event.modifierFlags.contains(.shift)
        case 59, 62:
            return event.modifierFlags.contains(.control)
        case UInt16(kVK_Function):
            return event.modifierFlags.contains(.function)
        default:
            return false
        }
    }

    private func keyCodeToName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case UInt16(kVK_Function): return "fn"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return ""
        }
    }
}

struct HotkeyConflictStatusView: View {
    let status: HotkeyConflictStatus
    let locale: Locale

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(message)
                .foregroundStyle(tint)
        }
        .font(.caption)
        .accessibilityLabel(message)
    }

    private var iconName: String {
        switch status {
        case .noConflict:
            return "checkmark.circle.fill"
        case .pindropConflict:
            return "exclamationmark.triangle.fill"
        case .systemShortcut:
            return "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .noConflict:
            return .green
        case .pindropConflict:
            return .orange
        case .systemShortcut:
            return .secondary
        }
    }

    private var message: String {
        switch status {
        case .noConflict:
            return localized("No conflicts found", locale: locale)
        case .pindropConflict(let conflictingSlot):
            return String(
                format: localized("Conflicts with %@", locale: locale),
                localized(conflictingSlot.displayName, locale: locale)
            )
        case .systemShortcut(let name):
            return String(
                format: localized("May conflict with a system shortcut (%@)", locale: locale),
                name
            )
        }
    }
}

struct HotkeyRecorderRow: View {
    @Environment(\.locale) private var locale

    let hotkey: String
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(hotkey.isEmpty ? localized("Not set", locale: locale) : hotkey)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(hotkey.isEmpty ? .secondary : .primary)
                .frame(minWidth: 90, alignment: .trailing)

            Button(action: onRecord) {
                Text(
                    isRecording
                        ? localized("Press keys…", locale: locale)
                        : localized("Record", locale: locale)
                )
            }

            if isRecording {
                Text(localized("Press Esc to cancel", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !hotkey.isEmpty && !isRecording {
                Button(role: .destructive, action: onClear) {
                    Image(systemName: "xmark.circle")
                }
                .help(localized("Clear shortcut", locale: locale))
            }
        }
    }
}

#Preview {
    HotkeysSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 560)
}
