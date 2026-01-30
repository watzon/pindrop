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
    @State private var isRecordingQuickCapture = false
    @State private var keyMonitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
            toggleHotkeyCard
            pushToTalkCard
            copyLastTranscriptCard
            quickCaptureCard
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
    
    private var quickCaptureCard: some View {
        SettingsCard(title: "Note Capture", icon: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quickly capture a note without switching apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HotkeyRecorderRow(
                    hotkey: settings.quickCaptureHotkey,
                    isRecording: isRecordingQuickCapture,
                    onRecord: { startRecording(forQuickCapture: true) },
                    onClear: {
                        settings.quickCaptureHotkey = ""
                        settings.quickCaptureHotkeyCode = 0
                        settings.quickCaptureHotkeyModifiers = 0
                    }
                )
            }
        }
    }
    
    private func startRecording(forToggle: Bool = false, forCopyLastTranscript: Bool = false, forQuickCapture: Bool = false) {
        stopRecording()

        if forToggle {
            isRecordingToggle = true
            isRecordingPushToTalk = false
            isRecordingCopyLastTranscript = false
            isRecordingQuickCapture = false
        } else if forCopyLastTranscript {
            isRecordingToggle = false
            isRecordingPushToTalk = false
            isRecordingCopyLastTranscript = true
            isRecordingQuickCapture = false
        } else if forQuickCapture {
            isRecordingToggle = false
            isRecordingPushToTalk = false
            isRecordingCopyLastTranscript = false
            isRecordingQuickCapture = true
        } else {
            isRecordingToggle = false
            isRecordingPushToTalk = true
            isRecordingCopyLastTranscript = false
            isRecordingQuickCapture = false
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Cancel recording on Escape
            if event.type == .keyDown && event.keyCode == 53 {
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
                } else if forQuickCapture {
                    settings.quickCaptureHotkey = hotkeyString
                    settings.quickCaptureHotkeyCode = Int(event.keyCode)
                    settings.quickCaptureHotkeyModifiers = Int(carbonModifiers)
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
        isRecordingQuickCapture = false
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
