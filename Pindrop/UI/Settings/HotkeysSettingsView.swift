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
    /// Last-captured conflict status kept visible after key-up so the user can read it.
    @State private var lastConflictStatusBySlot: [HotkeySlot: HotkeyConflictStatus] = [:]

    private struct PendingHotkeyCapture {
        let hotkeyString: String
        let keyCode: UInt16
        let modifiers: UInt32
        let isModifierOnly: Bool
    }

    /// Design primary rows (spec §13 / U8).
    private var primarySlots: [(HotkeySlot, String, String, String, () -> Void)] {
        [
            (
                .toggleRecording,
                localized("Toggle dictation", locale: locale),
                localized("Press once to start recording, then press again to stop and transcribe.", locale: locale),
                settings.toggleHotkey,
                {
                    settings.updateToggleHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.toggleRecording] = nil
                }
            ),
            (
                .pushToTalk,
                localized("Push to talk", locale: locale),
                localized("Hold the shortcut to record, then release to transcribe.", locale: locale),
                settings.pushToTalkHotkey,
                {
                    settings.updatePushToTalkHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.pushToTalk] = nil
                }
            ),
            (
                .copyLastTranscript,
                localized("Copy last transcript", locale: locale),
                localized("Copy the most recent transcript to the clipboard.", locale: locale),
                settings.copyLastTranscriptHotkey,
                {
                    settings.updateCopyLastTranscriptHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.copyLastTranscript] = nil
                }
            ),
            (
                .openLibrary,
                localized("Open Library", locale: locale),
                localized("Show the main window and open the Library.", locale: locale),
                settings.openLibraryHotkey,
                {
                    settings.updateOpenLibraryHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.openLibrary] = nil
                }
            ),
            (
                .cancelOperation,
                localized("Cancel Operation", locale: locale),
                localized("Cancel the active recording, transcription, or enhancement.", locale: locale),
                settings.cancelOperationHotkey,
                {
                    settings.updateCancelOperationHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.cancelOperation] = nil
                }
            ),
        ]
    }

    private var noteSlots: [(HotkeySlot, String, String, String, () -> Void)] {
        [
            (
                .quickCapturePTT,
                localized("Note Capture — Hold", locale: locale),
                localized("Hold to record, then release to open the note editor with the transcription.", locale: locale),
                settings.quickCapturePTTHotkey,
                {
                    settings.updateQuickCapturePTTHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.quickCapturePTT] = nil
                }
            ),
            (
                .quickCaptureToggle,
                localized("Note Capture — Toggle", locale: locale),
                localized("Press once to start recording, then again to open the note editor.", locale: locale),
                settings.quickCaptureToggleHotkey,
                {
                    settings.updateQuickCaptureToggleHotkey("", keyCode: 0, modifiers: 0)
                    lastConflictStatusBySlot[.quickCaptureToggle] = nil
                }
            ),
        ]
    }

    var body: some View {
        SettingsPaneStack {
            SettingsGroupCard {
                ForEach(Array(primarySlots.enumerated()), id: \.element.0) { index, item in
                    hotkeyRow(
                        slot: item.0,
                        title: item.1,
                        detail: item.2,
                        hotkey: item.3,
                        onClear: item.4,
                        showSeparator: index < primarySlots.count - 1
                    )
                }
            }

            Text(aggregateConflictLine)
                .font(AppTypography.caption)
                .foregroundStyle(aggregateConflictColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityLabel(aggregateConflictLine)

            SettingsGroupCard {
                ForEach(Array(noteSlots.enumerated()), id: \.element.0) { index, item in
                    hotkeyRow(
                        slot: item.0,
                        title: item.1,
                        detail: item.2,
                        hotkey: item.3,
                        onClear: item.4,
                        showSeparator: index < noteSlots.count - 1
                    )
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    /// Captured statuses when available; otherwise a live check on configured assignments,
    /// so the pane-level line and its color always agree.
    private var aggregateConflictStatuses: [HotkeyConflictStatus] {
        let captured = HotkeySlot.allCases.compactMap { conflictStatus(for: $0) }
        if !captured.isEmpty { return captured }

        let assignments = settings.configuredHotkeyAssignments()
        return HotkeySlot.allCases.compactMap { slot -> HotkeyConflictStatus? in
            guard let assignment = assignments.first(where: { $0.slot == slot }) else { return nil }
            return HotkeyConflictChecker.check(
                keyCode: assignment.keyCode,
                modifiers: assignment.modifiers,
                slot: slot,
                assignments: assignments
            )
        }
    }

    private var aggregateConflictLine: String {
        SettingsHotkeyConflictPresentation.aggregateStatus(
            statuses: aggregateConflictStatuses,
            locale: locale
        )
    }

    private var aggregateConflictColor: Color {
        let statuses = aggregateConflictStatuses
        if statuses.contains(where: {
            if case .pindropConflict = $0 { return true }
            return false
        }) {
            return AppColors.warning
        }
        if statuses.contains(where: {
            if case .systemShortcut = $0 { return true }
            return false
        }) {
            return AppColors.textSecondary
        }
        return AppColors.success
    }

    private func hotkeyRow(
        slot: HotkeySlot,
        title: String,
        detail: String,
        hotkey: String,
        onClear: @escaping () -> Void,
        showSeparator: Bool
    ) -> some View {
        let isRecording = recordingSlot == slot
        let status = conflictStatus(for: slot)

        return SettingsRow(showSeparator: showSeparator) {
            VStack(alignment: .leading, spacing: 4) {
                SettingsRowLabel(title: title, subtitle: detail)
                if let status {
                    HotkeyConflictStatusView(status: status, locale: locale)
                }
            }
        } control: {
            HotkeyRecorderRow(
                hotkey: hotkey,
                isRecording: isRecording,
                onRecord: { startRecording(for: slot) },
                onClear: onClear
            )
        }
    }

    /// Live status while capturing; otherwise the last-captured status for this slot (if any).
    private func conflictStatus(for slot: HotkeySlot) -> HotkeyConflictStatus? {
        if recordingSlot == slot, let capture = pendingHotkeyCapture {
            return HotkeyConflictChecker.check(
                keyCode: UInt32(capture.keyCode),
                modifiers: capture.modifiers,
                slot: slot,
                assignments: settings.configuredHotkeyAssignments()
            )
        }
        return lastConflictStatusBySlot[slot]
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

        lastConflictStatusBySlot[slot] = HotkeyConflictChecker.check(
            keyCode: UInt32(capture.keyCode),
            modifiers: capture.modifiers,
            slot: slot,
            assignments: settings.configuredHotkeyAssignments()
        )

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
        case .cancelOperation:
            settings.updateCancelOperationHotkey(hotkey, keyCode: keyCode, modifiers: modifiers)
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

        let keyCode = event.keyCode
        if keyCode == 59 { parts.append("⌃L") }
        else if keyCode == 62 { parts.append("⌃R") }
        else if keyCode == 58 { parts.append("⌥L") }
        else if keyCode == 61 { parts.append("⌥R") }
        else if keyCode == 56 { parts.append("⇧L") }
        else if keyCode == 60 { parts.append("⇧R") }
        else if keyCode == 55 { parts.append("⌘L") }
        else if keyCode == 54 { parts.append("⌘R") }
        else if keyCode == UInt16(kVK_Function) { parts.append("fn") }
        else {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.command) { parts.append("⌘") }
            if modifiers.contains(.function) { parts.append("fn") }

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
        .font(AppTypography.caption)
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
            return AppColors.success
        case .pindropConflict:
            return AppColors.warning
        case .systemShortcut:
            return AppColors.textSecondary
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
            if isRecording {
                SettingsKbdChip(text: localized("Press keys…", locale: locale))
                    .foregroundStyle(AppColors.warning)
            } else if hotkey.isEmpty {
                Text(localized("Not set", locale: locale))
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                SettingsKbdChip(text: hotkey)
            }

            Button(action: onRecord) {
                SettingsMenuButton(
                    title: isRecording
                        ? localized("Listening…", locale: locale)
                        : localized("Record", locale: locale),
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)

            if !hotkey.isEmpty && !isRecording {
                Button(role: .destructive, action: onClear) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(localized("Clear shortcut", locale: locale))
                .accessibilityLabel(localized("Clear shortcut", locale: locale))
            }
        }
    }
}

#Preview {
    HotkeysSettingsView(settings: SettingsStore())
        .frame(width: 620, height: 560)
        .background(AppColors.windowBackground)
        .themeRefresh()
}
