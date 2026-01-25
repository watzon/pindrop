//
//  HotkeyManager.swift
//  Pindrop
//
//  Created on 1/25/26.
//

import Foundation
import Carbon
import os.log

final class HotkeyManager {
    
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
        let callback: () -> Void
    }
    
    private struct RegisteredHotkey {
        let configuration: HotkeyConfiguration
        let eventHotKeyRef: EventHotKeyRef
        let eventHotKeyID: EventHotKeyID
    }
    
    private var registeredHotkeys: [String: RegisteredHotkey] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.pindrop.app", category: "HotkeyManager")
    
    init() {
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
        callback: @escaping () -> Void
    ) -> Bool {
        if registeredHotkeys[identifier] != nil {
            logger.error("Hotkey with identifier '\(identifier)' is already registered")
            return false
        }
        
        let configuration = HotkeyConfiguration(
            keyCode: keyCode,
            modifiers: modifiers,
            identifier: identifier,
            callback: callback
        )
        
        var eventHotKeyID = EventHotKeyID()
        eventHotKeyID.signature = OSType(("PNDR" as NSString).utf8String!.withMemoryRebound(to: UInt8.self, capacity: 4) { ptr in
            return UInt32(ptr[0]) << 24 | UInt32(ptr[1]) << 16 | UInt32(ptr[2]) << 8 | UInt32(ptr[3])
        })
        eventHotKeyID.id = UInt32(identifier.hashValue)
        
        var eventHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
        
        guard status == noErr, let hotKeyRef = eventHotKeyRef else {
            logger.error("Failed to register hotkey '\(identifier)': OSStatus \(status)")
            return false
        }
        
        let registeredHotkey = RegisteredHotkey(
            configuration: configuration,
            eventHotKeyRef: hotKeyRef,
            eventHotKeyID: eventHotKeyID
        )
        
        registeredHotkeys[identifier] = registeredHotkey
        logger.info("Successfully registered hotkey '\(identifier)'")
        
        return true
    }
    
    func unregisterHotkey(identifier: String) -> Bool {
        guard let registeredHotkey = registeredHotkeys[identifier] else {
            logger.warning("Attempted to unregister nonexistent hotkey '\(identifier)'")
            return false
        }
        
        let status = UnregisterEventHotKey(registeredHotkey.eventHotKeyRef)
        
        guard status == noErr else {
            logger.error("Failed to unregister hotkey '\(identifier)': OSStatus \(status)")
            return false
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
        
        for (_, registeredHotkey) in registeredHotkeys {
            if registeredHotkey.eventHotKeyID.signature == hotKeyID.signature &&
               registeredHotkey.eventHotKeyID.id == hotKeyID.id {
                
                DispatchQueue.main.async {
                    registeredHotkey.configuration.callback()
                }
                
                return noErr
            }
        }
        
        return OSStatus(eventNotHandledErr)
    }
}
