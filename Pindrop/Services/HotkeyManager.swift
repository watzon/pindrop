//
//  HotkeyManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import Carbon
import CoreGraphics
import os.log

// MARK: - Hotkey Registration Protocol

protocol HotkeyRegistrationProtocol {
    func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool
    func unregisterHotkey(id: UInt32) -> Bool
}

// MARK: - Carbon Events Implementation

final class CarbonHotkeyRegistration: HotkeyRegistrationProtocol {
    private var registeredRefs: [UInt32: EventHotKeyRef] = [:]
    
    func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var eventHotKeyID = EventHotKeyID()
        eventHotKeyID.signature = OSType(("PNDR" as NSString).utf8String!.withMemoryRebound(to: UInt8.self, capacity: 4) { ptr in
            return UInt32(ptr[0]) << 24 | UInt32(ptr[1]) << 16 | UInt32(ptr[2]) << 8 | UInt32(ptr[3])
        })
        eventHotKeyID.id = id
        
        var eventHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
        
        guard status == noErr, let hotKeyRef = eventHotKeyRef else {
            return false
        }
        
        registeredRefs[id] = hotKeyRef
        return true
    }
    
    func unregisterHotkey(id: UInt32) -> Bool {
        guard let hotKeyRef = registeredRefs[id] else {
            return false
        }
        
        let status = UnregisterEventHotKey(hotKeyRef)
        
        guard status == noErr else {
            return false
        }
        
        registeredRefs.removeValue(forKey: id)
        return true
    }
}

// MARK: - HotkeyManager

final class HotkeyManager {
    
    enum HotkeyMode {
        case toggle
        case pushToTalk
    }
    
    struct ModifierFlags: OptionSet {
        let rawValue: UInt32
        
        static let command = ModifierFlags(rawValue: UInt32(cmdKey))
        static let option = ModifierFlags(rawValue: UInt32(optionKey))
        static let shift = ModifierFlags(rawValue: UInt32(shiftKey))
        static let control = ModifierFlags(rawValue: UInt32(controlKey))
    }
    
    struct HotkeyConfiguration {
        let keyCode: UInt32
        let modifiers: ModifierFlags
        let identifier: String
        let mode: HotkeyMode
        let onKeyDown: (() -> Void)?
        let onKeyUp: (() -> Void)?
        
        // Convenience initializer for toggle mode (backward compatibility)
        init(keyCode: UInt32, modifiers: ModifierFlags, identifier: String, callback: @escaping () -> Void) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.identifier = identifier
            self.mode = .toggle
            self.onKeyDown = callback
            self.onKeyUp = nil
        }
        
        // Initializer for push-to-talk mode
        init(keyCode: UInt32, modifiers: ModifierFlags, identifier: String, mode: HotkeyMode, onKeyDown: (() -> Void)?, onKeyUp: (() -> Void)?) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.identifier = identifier
            self.mode = mode
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
        }
    }
    
    private struct RegisteredHotkey {
        let configuration: HotkeyConfiguration
        let eventHotKeyID: EventHotKeyID
        let usesCarbonRegistration: Bool
        var isKeyCurrentlyPressed: Bool = false
    }
    
    private var registeredHotkeys: [String: RegisteredHotkey] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.pindrop.app", category: "HotkeyManager")
    private let registration: HotkeyRegistrationProtocol
    
    init(registration: HotkeyRegistrationProtocol = CarbonHotkeyRegistration()) {
        self.registration = registration
        setupEventHandler()
    }
    
    deinit {
        unregisterAll()
        removeEventHandler()
    }
    
    func registerHotkey(
        keyCode: UInt32,
        modifiers: ModifierFlags,
        identifier: String,
        mode: HotkeyMode = .toggle,
        onKeyDown: (() -> Void)? = nil,
        onKeyUp: (() -> Void)? = nil
    ) -> Bool {
        if registeredHotkeys[identifier] != nil {
            logger.error("Hotkey with identifier '\(identifier)' is already registered")
            return false
        }
        
        let configuration = HotkeyConfiguration(
            keyCode: keyCode,
            modifiers: modifiers,
            identifier: identifier,
            mode: mode,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
        
        // Use truncatingIfNeeded to safely convert hash to UInt32 (handles negative values and overflow)
        let hotkeyID = UInt32(truncatingIfNeeded: identifier.hashValue)
        
        let usesCarbonRegistration = modifierMask(for: keyCode) == nil
        if usesCarbonRegistration {
            let success = registration.registerHotkey(
                id: hotkeyID,
                keyCode: keyCode,
                modifiers: modifiers.rawValue
            )
            
            guard success else {
                logger.error("Failed to register hotkey '\(identifier)'")
                return false
            }
        }
        
        var eventHotKeyID = EventHotKeyID()
        eventHotKeyID.signature = OSType(("PNDR" as NSString).utf8String!.withMemoryRebound(to: UInt8.self, capacity: 4) { ptr in
            return UInt32(ptr[0]) << 24 | UInt32(ptr[1]) << 16 | UInt32(ptr[2]) << 8 | UInt32(ptr[3])
        })
        eventHotKeyID.id = hotkeyID
        
        let registeredHotkey = RegisteredHotkey(
            configuration: configuration,
            eventHotKeyID: eventHotKeyID,
            usesCarbonRegistration: usesCarbonRegistration
        )
        
        registeredHotkeys[identifier] = registeredHotkey
        if usesCarbonRegistration {
            logger.info("Successfully registered hotkey '\(identifier)'")
        } else {
            logger.info("Registered modifier-only hotkey '\(identifier)' with keyCode=\(keyCode)")
        }
        
        return true
    }
    
    func unregisterHotkey(identifier: String) -> Bool {
        guard let registeredHotkey = registeredHotkeys[identifier] else {
            logger.warning("Attempted to unregister nonexistent hotkey '\(identifier)'")
            return false
        }

        if registeredHotkey.usesCarbonRegistration {
            let hotkeyID = registeredHotkey.eventHotKeyID.id
            let success = registration.unregisterHotkey(id: hotkeyID)
            
            guard success else {
                logger.error("Failed to unregister hotkey '\(identifier)'")
                return false
            }
        }
        
        registeredHotkeys.removeValue(forKey: identifier)
        logger.info("Successfully unregistered hotkey '\(identifier)'")
        
        return true
    }
    
    func unregisterAll() {
        let identifiers = Array(registeredHotkeys.keys)
        for identifier in identifiers {
            _ = unregisterHotkey(identifier: identifier)
        }
    }
    
    func isHotkeyRegistered(identifier: String) -> Bool {
        return registeredHotkeys[identifier] != nil
    }
    
    func getHotkeyConfiguration(identifier: String) -> HotkeyConfiguration? {
        return registeredHotkeys[identifier]?.configuration
    }
    
    func convertToCarbonModifiers(_ modifiers: ModifierFlags) -> UInt32 {
        return modifiers.rawValue
    }

    func handleModifierFlagsChanged(event: CGEvent) {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard let modifierMask = modifierMask(for: keyCode) else { return }

        let isKeyDown = event.flags.contains(modifierMask)
        let eventModifiers = modifierFlagsFrom(event.flags)

        DispatchQueue.main.async { [weak self] in
            self?.handleModifierKeyEvent(
                keyCode: keyCode,
                eventModifiers: eventModifiers,
                isKeyDown: isKeyDown
            )
        }
    }
    
    private func setupEventHandler() {
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        
        let callback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(event: event)
        }
        
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventSpec.count,
            eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        
        if status == noErr {
            eventHandlerRef = handlerRef
            logger.info("Event handler installed successfully")
        } else {
            logger.error("Failed to install event handler: OSStatus \(status)")
        }
    }
    
    private func removeEventHandler() {
        guard let handlerRef = eventHandlerRef else { return }
        
        let status = RemoveEventHandler(handlerRef)
        if status == noErr {
            eventHandlerRef = nil
            logger.info("Event handler removed successfully")
        } else {
            logger.error("Failed to remove event handler: OSStatus \(status)")
        }
    }
    
    private func handleHotkeyEvent(event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }
        
        let eventKind = GetEventKind(event)
        let isKeyDown = (eventKind == UInt32(kEventHotKeyPressed))
        let isKeyUp = (eventKind == UInt32(kEventHotKeyReleased))
        
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else {
            logger.error("Failed to get event parameter: OSStatus \(status)")
            return OSStatus(eventNotHandledErr)
        }
        
        for (identifier, var registeredHotkey) in registeredHotkeys {
            if registeredHotkey.eventHotKeyID.signature == hotKeyID.signature &&
               registeredHotkey.eventHotKeyID.id == hotKeyID.id {
                
                let config = registeredHotkey.configuration
                
                if isKeyDown && registeredHotkey.isKeyCurrentlyPressed {
                    return noErr
                }
                
                if isKeyDown {
                    registeredHotkey.isKeyCurrentlyPressed = true
                    registeredHotkeys[identifier] = registeredHotkey
                } else if isKeyUp {
                    registeredHotkey.isKeyCurrentlyPressed = false
                    registeredHotkeys[identifier] = registeredHotkey
                }
                
                DispatchQueue.main.async {
                    switch config.mode {
                    case .toggle:
                        if isKeyDown {
                            config.onKeyDown?()
                        }
                    case .pushToTalk:
                        if isKeyDown {
                            config.onKeyDown?()
                        } else if isKeyUp {
                            config.onKeyUp?()
                        }
                    }
                }
                
                return noErr
            }
        }
        
        return OSStatus(eventNotHandledErr)
    }

    private func handleModifierKeyEvent(
        keyCode: UInt32,
        eventModifiers: ModifierFlags,
        isKeyDown: Bool
    ) {
        for (identifier, var registeredHotkey) in registeredHotkeys {
            guard !registeredHotkey.usesCarbonRegistration else { continue }
            guard registeredHotkey.configuration.keyCode == keyCode else { continue }

            let config = registeredHotkey.configuration

            if isKeyDown {
                guard eventModifiers == config.modifiers else { continue }
                guard !registeredHotkey.isKeyCurrentlyPressed else { continue }

                registeredHotkey.isKeyCurrentlyPressed = true
                registeredHotkeys[identifier] = registeredHotkey

                config.onKeyDown?()
            } else if registeredHotkey.isKeyCurrentlyPressed {
                registeredHotkey.isKeyCurrentlyPressed = false
                registeredHotkeys[identifier] = registeredHotkey

                if config.mode == .pushToTalk {
                    config.onKeyUp?()
                }
            }
        }
    }

    private func modifierMask(for keyCode: UInt32) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            return .maskCommand
        case 58, 61:
            return .maskAlternate
        case 56, 60:
            return .maskShift
        case 59, 62:
            return .maskControl
        default:
            return nil
        }
    }

    private func modifierFlagsFrom(_ flags: CGEventFlags) -> ModifierFlags {
        var modifiers: ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return modifiers
    }
}
