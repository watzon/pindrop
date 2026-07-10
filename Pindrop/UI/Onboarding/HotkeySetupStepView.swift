//
//  HotkeySetupStepView.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AppKit
import Carbon
import SwiftUI

struct HotkeySetupStepView: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.locale) private var locale
    @State private var isCapturing = false
    @State private var keyMonitor: Any?
    @State private var pendingCapture: PendingCapture?
    @State private var activeModifierKeyCodes = Set<UInt16>()
    @State private var conflictStatus: HotkeyConflictStatus = .noConflict

    private struct PendingCapture {
        let display: String
        let keyCode: UInt16
        let modifiers: UInt32
        let isModifierOnly: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(localized("Keyboard Shortcuts", locale: locale))
                .font(OnboardingType.stepHeading)
                .tracking(-0.42)
                .foregroundStyle(AppColors.textPrimary)

            Text(localized("Your hotkeys are ready to use.\nYou can customize them later in Settings.", locale: locale))
                .font(OnboardingType.stepSubtitle)
                .lineSpacing(3)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Button(action: startCapture) {
                HStack(spacing: 10) {
                    ForEach(Array(displayedKeycaps.enumerated()), id: \.offset) { _, keycap in
                        Text(keycap)
                            .font(FontLoader.font(family: .jetbrainsMono, size: 24, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.vertical, 14)
                            .padding(.horizontal, keycap.count > 1 ? 30 : 22)
                            .background(AppColors.contentBackground, in: .rect(cornerRadius: 12))
                    }
                }
            }
            .buttonStyle(.plain)
            .keyboardFocusRing(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 34)

            Text(localized("Press a different combination to change it", locale: locale))
                .font(AppTypography.captionLarge)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 22)

            HotkeyConflictStatusView(status: conflictStatus, locale: locale)
                .padding(.top, 8)

            HStack(spacing: 14) {
                OnboardingPrimaryButton(title: localized("Continue", locale: locale), icon: nil, action: onContinue)
                OnboardingGhostButton(title: localized("Skip for Now", locale: locale), action: onSkip)
            }
            .padding(.top, 26)
        }
        .onAppear(perform: refreshConflictStatus)
        .onDisappear(perform: stopCapture)
    }

    private var displayedKeycaps: [String] {
        if isCapturing {
            return [localized("Press keys…", locale: locale)]
        }
        let hotkey = settings.toggleHotkey
        guard !hotkey.isEmpty else { return [localized("Not Set", locale: locale)] }

        var remainder = hotkey.replacingOccurrences(of: " ", with: "")
        var components: [String] = []
        let tokens = ["⌃L", "⌃R", "⌥L", "⌥R", "⇧L", "⇧R", "⌘L", "⌘R", "fn", "⌃", "⌥", "⇧", "⌘"]
        while !remainder.isEmpty {
            if let token = tokens.first(where: { remainder.hasPrefix($0) }) {
                components.append(token)
                remainder.removeFirst(token.count)
            } else {
                components.append(remainder)
                break
            }
        }
        return components
    }

    private func refreshConflictStatus() {
        conflictStatus = HotkeyConflictChecker.check(
            keyCode: UInt32(settings.toggleHotkeyCode),
            modifiers: UInt32(settings.toggleHotkeyModifiers),
            slot: .toggleRecording,
            assignments: settings.configuredHotkeyAssignments()
        )
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true
        HotkeyManager.setHotkeyCaptureInProgress(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handleCaptureEvent(event)
        }
    }

    private func handleCaptureEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown && event.keyCode == 53 {
            stopCapture()
            return nil
        }

        if event.type == .flagsChanged, isModifierKeyCode(event.keyCode) {
            if modifierKeyIsDown(event) {
                activeModifierKeyCodes.insert(event.keyCode)
                guard isAllowedSoloModifierKeyCode(event.keyCode) else { return nil }
                pendingCapture = PendingCapture(
                    display: buildHotkeyString(from: event),
                    keyCode: event.keyCode,
                    modifiers: carbonModifiers(from: event.modifierFlags),
                    isModifierOnly: true
                )
            } else {
                activeModifierKeyCodes.remove(event.keyCode)
                if activeModifierKeyCodes.isEmpty,
                   let capture = pendingCapture,
                   capture.isModifierOnly {
                    apply(capture)
                }
            }
            return nil
        }

        if event.type == .keyDown, !isModifierKeyCode(event.keyCode) {
            let modifiers = carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 || keyCodeToName(event.keyCode).hasPrefix("F") else { return nil }
            pendingCapture = PendingCapture(
                display: buildHotkeyString(from: event),
                keyCode: event.keyCode,
                modifiers: modifiers,
                isModifierOnly: false
            )
            return nil
        }

        if event.type == .keyUp,
           let capture = pendingCapture,
           !capture.isModifierOnly,
           capture.keyCode == event.keyCode {
            apply(capture)
            return nil
        }
        return nil
    }

    private func apply(_ capture: PendingCapture) {
        conflictStatus = HotkeyConflictChecker.check(
            keyCode: UInt32(capture.keyCode),
            modifiers: capture.modifiers,
            slot: .toggleRecording,
            assignments: settings.configuredHotkeyAssignments()
        )
        settings.updateToggleHotkey(
            capture.display,
            keyCode: Int(capture.keyCode),
            modifiers: Int(capture.modifiers)
        )
        stopCapture()
    }

    private func stopCapture() {
        HotkeyManager.setHotkeyCaptureInProgress(false)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        pendingCapture = nil
        activeModifierKeyCodes.removeAll()
        isCapturing = false
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.function) { result |= UInt32(kEventKeyModifierFnMask) }
        return result
    }

    private func buildHotkeyString(from event: NSEvent) -> String {
        switch event.keyCode {
        case 59: return "⌃L"
        case 62: return "⌃R"
        case 58: return "⌥L"
        case 61: return "⌥R"
        case 56: return "⇧L"
        case 60: return "⇧R"
        case 55: return "⌘L"
        case 54: return "⌘R"
        case UInt16(kVK_Function): return "fn"
        default:
            var parts: [String] = []
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            if flags.contains(.function) { parts.append("fn") }
            let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
            let key = characters.first.map(String.init) ?? keyCodeToName(event.keyCode)
            parts.append(key.isEmpty ? keyCodeToName(event.keyCode) : key)
            return parts.joined()
        }
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 60, 58, 61, 59, 62, UInt16(kVK_Function)].contains(keyCode)
    }

    private func isAllowedSoloModifierKeyCode(_ keyCode: UInt16) -> Bool {
        isModifierKeyCode(keyCode)
    }

    private func modifierKeyIsDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 54, 55: return event.modifierFlags.contains(.command)
        case 58, 61: return event.modifierFlags.contains(.option)
        case 56, 60: return event.modifierFlags.contains(.shift)
        case 59, 62: return event.modifierFlags.contains(.control)
        case UInt16(kVK_Function): return event.modifierFlags.contains(.function)
        default: return false
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

#if DEBUG
struct HotkeySetupStepView_Previews: PreviewProvider {
    static var previews: some View {
        HotkeySetupStepView(settings: SettingsStore(), onContinue: {}, onSkip: {})
            .frame(width: 760, height: 500)
            .background(AppColors.windowBackground)
    }
}
#endif
