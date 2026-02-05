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
    @State private var isRecordingToggle = false
    @State private var isRecordingPushToTalk = false
    @State private var isRecordingCopyLastTranscript = false
    @State private var isRecordingQuickCapturePTT = false
    @State private var isRecordingQuickCaptureToggle = false
    @State private var keyMonitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
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
        SettingsCard(title: "Toggle Recording", icon: "record.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press once to start recording, press again to stop and transcribe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.toggleHotkey,
                    isRecording: isRecordingToggle,
                    onRecord: { startRecording(forToggle: true) },
                    onClear: {
                        settings.toggleHotkey = ""
                        settings.toggleHotkeyCode = 0
                        settings.toggleHotkeyModifiers = 0
                    }
                )
            }
        }
    }
    
    private var pushToTalkCard: some View {
        SettingsCard(title: "Push-to-Talk", icon: "hand.tap") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold to record, release to stop and transcribe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.pushToTalkHotkey,
                    isRecording: isRecordingPushToTalk,
                    onRecord: { startRecording(forToggle: false) },
                    onClear: {
                        settings.pushToTalkHotkey = ""
                        settings.pushToTalkHotkeyCode = 0
                        settings.pushToTalkHotkeyModifiers = 0
                    }
                )
            }
        }
    }

    private var copyLastTranscriptCard: some View {
        SettingsCard(title: "Copy Last Transcript", icon: "doc.on.clipboard") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Copy the most recent transcript to the clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HotkeyRecorderRow(
                    hotkey: settings.copyLastTranscriptHotkey,
                    isRecording: isRecordingCopyLastTranscript,
                    onRecord: { startRecording(forCopyLastTranscript: true) },
                    onClear: {
                        settings.copyLastTranscriptHotkey = ""
                        settings.copyLastTranscriptHotkeyCode = 0
                        settings.copyLastTranscriptHotkeyModifiers = 0
                    }
                )
            }
        }
    }
    
    private var quickCapturePTTCard: some View {
        SettingsCard(title: "Note Capture (Push-to-Talk)", icon: "hand.tap") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold to record, release to open note editor with transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.quickCapturePTTHotkey,
                    isRecording: isRecordingQuickCapturePTT,
                    onRecord: { startRecording(forQuickCapturePTT: true) },
                    onClear: {
                        settings.quickCapturePTTHotkey = ""
                        settings.quickCapturePTTHotkeyCode = 0
                        settings.quickCapturePTTHotkeyModifiers = 0
                    }
                )
            }
        }
    }

    private var quickCaptureToggleCard: some View {
        SettingsCard(title: "Note Capture (Toggle)", icon: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Press to start recording, press again to open note editor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.quickCaptureToggleHotkey,
                    isRecording: isRecordingQuickCaptureToggle,
                    onRecord: { startRecording(forQuickCaptureToggle: true) },
                    onClear: {
                        settings.quickCaptureToggleHotkey = ""
                        settings.quickCaptureToggleHotkeyCode = 0
                        settings.quickCaptureToggleHotkeyModifiers = 0
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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            if event.type == .flagsChanged {
                guard self.isModifierKeyCode(event.keyCode), self.modifierKeyIsDown(event) else {
                    return event
                }

                let hotkeyString = self.buildHotkeyString(from: event)
                let carbonModifiers = self.carbonModifiersFrom(event.modifierFlags)

                if forToggle {
                    settings.toggleHotkey = hotkeyString
                    settings.toggleHotkeyCode = Int(event.keyCode)
                    settings.toggleHotkeyModifiers = Int(carbonModifiers)
                } else if forCopyLastTranscript {
                    settings.copyLastTranscriptHotkey = hotkeyString
                    settings.copyLastTranscriptHotkeyCode = Int(event.keyCode)
                    settings.copyLastTranscriptHotkeyModifiers = Int(carbonModifiers)
                } else if forQuickCapturePTT {
                    settings.quickCapturePTTHotkey = hotkeyString
                    settings.quickCapturePTTHotkeyCode = Int(event.keyCode)
                    settings.quickCapturePTTHotkeyModifiers = Int(carbonModifiers)
                } else if forQuickCaptureToggle {
                    settings.quickCaptureToggleHotkey = hotkeyString
                    settings.quickCaptureToggleHotkeyCode = Int(event.keyCode)
                    settings.quickCaptureToggleHotkeyModifiers = Int(carbonModifiers)
                } else {
                    settings.pushToTalkHotkey = hotkeyString
                    settings.pushToTalkHotkeyCode = Int(event.keyCode)
                    settings.pushToTalkHotkeyModifiers = Int(carbonModifiers)
                }

                self.stopRecording()
                return nil
            }

            if event.type == .keyDown {
                let hotkeyString = self.buildHotkeyString(from: event)
                let carbonModifiers = self.carbonModifiersFrom(event.modifierFlags)

                if forToggle {
                    settings.toggleHotkey = hotkeyString
                    settings.toggleHotkeyCode = Int(event.keyCode)
                    settings.toggleHotkeyModifiers = Int(carbonModifiers)
                } else if forCopyLastTranscript {
                    settings.copyLastTranscriptHotkey = hotkeyString
                    settings.copyLastTranscriptHotkeyCode = Int(event.keyCode)
                    settings.copyLastTranscriptHotkeyModifiers = Int(carbonModifiers)
                } else if forQuickCapturePTT {
                    settings.quickCapturePTTHotkey = hotkeyString
                    settings.quickCapturePTTHotkeyCode = Int(event.keyCode)
                    settings.quickCapturePTTHotkeyModifiers = Int(carbonModifiers)
                } else if forQuickCaptureToggle {
                    settings.quickCaptureToggleHotkey = hotkeyString
                    settings.quickCaptureToggleHotkeyCode = Int(event.keyCode)
                    settings.quickCaptureToggleHotkeyModifiers = Int(carbonModifiers)
                } else {
                    settings.pushToTalkHotkey = hotkeyString
                    settings.pushToTalkHotkeyCode = Int(event.keyCode)
                    settings.pushToTalkHotkeyModifiers = Int(carbonModifiers)
                }

                self.stopRecording()
                return nil
            }
            return event
        }
    }
    
    private func carbonModifiersFrom(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
    
    private func stopRecording() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
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
        else {
            // Regular modifiers (for non-modifier keys)
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.command) { parts.append("⌘") }

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
        case 54, 55, 56, 60, 58, 61, 59, 62:
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
        HStack(spacing: 12) {
            HStack {
                if hotkey.isEmpty {
                    Text("Not set")
                        .foregroundStyle(.secondary)
                } else {
                    Text(hotkey)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            .frame(minWidth: 120, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Button(action: onRecord) {
                Text(isRecording ? "Press keys..." : "Record")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .orange : nil)

            if isRecording {
                Text("Press Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !hotkey.isEmpty && !isRecording {
                Button(role: .destructive, action: onClear) {
                    IconView(icon: .circleX, size: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
