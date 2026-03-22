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
    @State private var isRecordingToggle = false
    @State private var isRecordingPushToTalk = false
    @State private var isRecordingCopyLastTranscript = false
    @State private var isRecordingQuickCapturePTT = false
    @State private var isRecordingQuickCaptureToggle = false
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
        VStack(spacing: AppTheme.Spacing.xl) {
            toggleHotkeyCard
            pushToTalkCard
            copyLastTranscriptCard
            quickCapturePTTCard
            quickCaptureToggleCard
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private var toggleHotkeyCard: some View {
        SettingsCard(title: localized("Toggle Recording", locale: locale), icon: "record.circle", detail: localized("Press once to start recording, then press again to stop and transcribe.", locale: locale)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(localized("Press once to start recording, press again to stop and transcribe", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.toggleHotkey,
                    isRecording: isRecordingToggle,
                    onRecord: { startRecording(forToggle: true) },
                    onClear: {
                        settings.updateToggleHotkey("", keyCode: 0, modifiers: 0)
                    }
                )
            }
        }
    }
    
    private var pushToTalkCard: some View {
        SettingsCard(title: localized("Push-to-Talk", locale: locale), icon: "hand.tap", detail: localized("Hold the shortcut to record, then release to transcribe.", locale: locale)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(localized("Hold to record, release to stop and transcribe", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.pushToTalkHotkey,
                    isRecording: isRecordingPushToTalk,
                    onRecord: { startRecording(forToggle: false) },
                    onClear: {
                        settings.updatePushToTalkHotkey("", keyCode: 0, modifiers: 0)
                    }
                )
            }
        }
    }

    private var copyLastTranscriptCard: some View {
        SettingsCard(title: localized("Copy Last Transcript", locale: locale), icon: "doc.on.clipboard", detail: localized("Quickly pull your latest transcript back to the clipboard.", locale: locale)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(localized("Copy the most recent transcript to the clipboard", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                HotkeyRecorderRow(
                    hotkey: settings.copyLastTranscriptHotkey,
                    isRecording: isRecordingCopyLastTranscript,
                    onRecord: { startRecording(forCopyLastTranscript: true) },
                    onClear: {
                        settings.updateCopyLastTranscriptHotkey("", keyCode: 0, modifiers: 0)
                    }
                )
            }
        }
    }
    
    private var quickCapturePTTCard: some View {
        SettingsCard(title: localized("Note Capture (Push-to-Talk)", locale: locale), icon: "hand.tap", detail: localized("Capture directly into the note editor with a hold-to-record flow.", locale: locale)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(localized("Hold to record, release to open note editor with transcription", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.quickCapturePTTHotkey,
                    isRecording: isRecordingQuickCapturePTT,
                    onRecord: { startRecording(forQuickCapturePTT: true) },
                    onClear: {
                        settings.updateQuickCapturePTTHotkey("", keyCode: 0, modifiers: 0)
                    }
                )
            }
        }
    }

    private var quickCaptureToggleCard: some View {
        SettingsCard(title: localized("Note Capture (Toggle)", locale: locale), icon: "note.text", detail: localized("Use a tap-to-start, tap-to-finish shortcut for note capture.", locale: locale)) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(localized("Press to start recording, press again to open note editor", locale: locale))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.quickCaptureToggleHotkey,
                    isRecording: isRecordingQuickCaptureToggle,
                    onRecord: { startRecording(forQuickCaptureToggle: true) },
                    onClear: {
                        settings.updateQuickCaptureToggleHotkey("", keyCode: 0, modifiers: 0)
                    }
                )
            }
        }
    }
    
    private func startRecording(
        forToggle: Bool = false,
        forCopyLastTranscript: Bool = false,
        forQuickCapturePTT: Bool = false,
        forQuickCaptureToggle: Bool = false
    ) {
        stopRecording()
        isRecordingToggle = forToggle
        isRecordingPushToTalk = !forToggle && !forCopyLastTranscript && !forQuickCapturePTT && !forQuickCaptureToggle
        isRecordingCopyLastTranscript = forCopyLastTranscript
        isRecordingQuickCapturePTT = forQuickCapturePTT
        isRecordingQuickCaptureToggle = forQuickCaptureToggle
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
                    self.applyCapturedHotkey(
                        capture,
                        forToggle: forToggle,
                        forCopyLastTranscript: forCopyLastTranscript,
                        forQuickCapturePTT: forQuickCapturePTT,
                        forQuickCaptureToggle: forQuickCaptureToggle
                    )
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
                self.applyCapturedHotkey(
                    capture,
                    forToggle: forToggle,
                    forCopyLastTranscript: forCopyLastTranscript,
                    forQuickCapturePTT: forQuickCapturePTT,
                    forQuickCaptureToggle: forQuickCaptureToggle
                )
                self.stopRecording()
                return nil
            }

            return nil
        }
    }
    private func applyCapturedHotkey(
        _ capture: PendingHotkeyCapture,
        forToggle: Bool,
        forCopyLastTranscript: Bool,
        forQuickCapturePTT: Bool,
        forQuickCaptureToggle: Bool
    ) {
        if forToggle {
            settings.updateToggleHotkey(capture.hotkeyString, keyCode: Int(capture.keyCode), modifiers: Int(capture.modifiers))
        } else if forCopyLastTranscript {
            settings.updateCopyLastTranscriptHotkey(capture.hotkeyString, keyCode: Int(capture.keyCode), modifiers: Int(capture.modifiers))
        } else if forQuickCapturePTT {
            settings.updateQuickCapturePTTHotkey(capture.hotkeyString, keyCode: Int(capture.keyCode), modifiers: Int(capture.modifiers))
        } else if forQuickCaptureToggle {
            settings.updateQuickCaptureToggleHotkey(capture.hotkeyString, keyCode: Int(capture.keyCode), modifiers: Int(capture.modifiers))
        } else {
            settings.updatePushToTalkHotkey(capture.hotkeyString, keyCode: Int(capture.keyCode), modifiers: Int(capture.modifiers))
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
        isRecordingToggle = false
        isRecordingPushToTalk = false
        isRecordingCopyLastTranscript = false
        isRecordingQuickCapturePTT = false
        isRecordingQuickCaptureToggle = false
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

struct HotkeyRecorderRow: View {
    let hotkey: String
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            HStack {
                if hotkey.isEmpty {
                    Text("Not set")
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text(hotkey)
                        .font(AppTypography.mono)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .frame(minWidth: 120, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.inputBorder, lineWidth: 1)
            )

            Button(action: onRecord) {
                Text(isRecording ? "Press keys..." : "Record")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? AppColors.warning : nil)

            if isRecording {
                Text("Press Esc to cancel")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
            }

            if !hotkey.isEmpty && !isRecording {
                Button(role: .destructive, action: onClear) {
                    IconView(icon: .circleX, size: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help("Clear hotkey")
            }
        }
    }
}

#Preview {
    HotkeysSettingsView(settings: SettingsStore())
        .padding()
        .frame(width: 500)
}
