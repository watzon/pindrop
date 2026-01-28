//
//  HotkeyManagerTests.swift
//  PindropTests
//
//  Created on 1/25/26.
//

import XCTest
import Carbon
@testable import Pindrop

// MARK: - Mock Hotkey Registration

final class MockHotkeyRegistration: HotkeyRegistrationProtocol {
    var registeredHotkeys: [(id: UInt32, keyCode: UInt32, modifiers: UInt32)] = []
    var unregisteredIds: [UInt32] = []
    var shouldSucceed = true
    var registerCallCount = 0
    var unregisterCallCount = 0
    
    func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        registerCallCount += 1
        guard shouldSucceed else { return false }
        registeredHotkeys.append((id, keyCode, modifiers))
        return true
    }
    
    func unregisterHotkey(id: UInt32) -> Bool {
        unregisterCallCount += 1
        guard shouldSucceed else { return false }
        unregisteredIds.append(id)
        registeredHotkeys.removeAll { $0.id == id }
        return true
    }
    
    func reset() {
        registeredHotkeys.removeAll()
        unregisteredIds.removeAll()
        shouldSucceed = true
        registerCallCount = 0
        unregisterCallCount = 0
    }
}

// MARK: - HotkeyManager Tests

final class HotkeyManagerTests: XCTestCase {
    
    var hotkeyManager: HotkeyManager!
    var mockRegistration: MockHotkeyRegistration!
    
    override func setUp() {
        super.setUp()
        mockRegistration = MockHotkeyRegistration()
        hotkeyManager = HotkeyManager(registration: mockRegistration)
    }
    
    override func tearDown() {
        hotkeyManager = nil
        mockRegistration = nil
        super.tearDown()
    }
    
    // MARK: - Registration Tests
    
    func testRegisterHotkey() {
        let callback: () -> Void = {}
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        XCTAssertTrue(result, "Hotkey registration should succeed")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should be registered")
        XCTAssertEqual(mockRegistration.registerCallCount, 1, "Should call registration once")
        XCTAssertEqual(mockRegistration.registeredHotkeys.count, 1, "Should have one registered hotkey")
        XCTAssertEqual(mockRegistration.registeredHotkeys[0].keyCode, 49, "Should register correct keyCode")
        XCTAssertEqual(mockRegistration.registeredHotkeys[0].modifiers, UInt32(optionKey), "Should register correct modifiers")
    }
    
    func testRegisterMultipleHotkeys() {
        let callback1: () -> Void = {}
        let callback2: () -> Void = {}
        
        let result1 = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback1
        )
        
        let result2 = hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command, .shift],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: callback2,
            onKeyUp: callback2
        )
        
        XCTAssertTrue(result1, "First hotkey should register")
        XCTAssertTrue(result2, "Second hotkey should register")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
    }
    
    func testRegisterDuplicateIdentifier() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        XCTAssertFalse(result, "Duplicate identifier registration should fail")
        XCTAssertEqual(mockRegistration.registerCallCount, 1, "Should only attempt registration once")
    }
    
    func testRegisterHotkeyFailure() {
        mockRegistration.shouldSucceed = false
        let callback: () -> Void = {}
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        XCTAssertFalse(result, "Registration should fail when mock returns false")
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should not be registered")
        XCTAssertEqual(mockRegistration.registerCallCount, 1, "Should attempt registration")
    }
    
    func testUnregisterHotkeyFailure() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        mockRegistration.shouldSucceed = false
        let result = hotkeyManager.unregisterHotkey(identifier: "toggle")
        
        XCTAssertFalse(result, "Unregistration should fail when mock returns false")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should still be registered")
    }
    
    // MARK: - Unregistration Tests
    
    func testUnregisterHotkey() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        let result = hotkeyManager.unregisterHotkey(identifier: "toggle")
        
        XCTAssertTrue(result, "Hotkey unregistration should succeed")
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should no longer be registered")
        XCTAssertEqual(mockRegistration.unregisterCallCount, 1, "Should call unregister once")
        XCTAssertEqual(mockRegistration.unregisteredIds.count, 1, "Should have one unregistered ID")
    }
    
    func testUnregisterNonexistentHotkey() {
        let result = hotkeyManager.unregisterHotkey(identifier: "nonexistent")
        
        XCTAssertFalse(result, "Unregistering nonexistent hotkey should return false")
        XCTAssertEqual(mockRegistration.unregisterCallCount, 0, "Should not call unregister for nonexistent hotkey")
    }
    
    func testUnregisterAll() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(keyCode: 49, modifiers: [.option], identifier: "toggle", onKeyDown: callback)
        _ = hotkeyManager.registerHotkey(keyCode: 50, modifiers: [.command], identifier: "pushToTalk", onKeyDown: callback)
        
        hotkeyManager.unregisterAll()
        
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
        XCTAssertEqual(mockRegistration.unregisterCallCount, 2, "Should unregister both hotkeys")
        XCTAssertEqual(mockRegistration.unregisteredIds.count, 2, "Should have two unregistered IDs")
    }
    
    // MARK: - Configuration Tests
    
    func testGetHotkeyConfiguration() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "toggle")
        
        XCTAssertNotNil(config, "Configuration should exist")
        XCTAssertEqual(config?.keyCode, 49)
        XCTAssertEqual(config?.modifiers, [.option])
        XCTAssertEqual(config?.identifier, "toggle")
    }
    
    func testGetNonexistentConfiguration() {
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "nonexistent")
        
        XCTAssertNil(config, "Configuration for nonexistent hotkey should be nil")
    }
    
    // MARK: - Modifier Conversion Tests
    
    func testModifierFlagsConversion() {
        // Test that our modifier flags convert correctly to Carbon modifiers
        let testCases: [(HotkeyManager.ModifierFlags, UInt32)] = [
            ([.command], UInt32(cmdKey)),
            ([.option], UInt32(optionKey)),
            ([.shift], UInt32(shiftKey)),
            ([.control], UInt32(controlKey)),
            ([.command, .option], UInt32(cmdKey | optionKey)),
            ([.command, .shift, .option], UInt32(cmdKey | shiftKey | optionKey))
        ]
        
        for (flags, expected) in testCases {
            let carbonFlags = hotkeyManager.convertToCarbonModifiers(flags)
            XCTAssertEqual(carbonFlags, expected, "Modifier conversion failed for \(flags)")
        }
    }
    
    // MARK: - Push-to-Talk Tests
    
    func testPushToTalkKeyDown() {
        var keyDownCalled = false
        var keyUpCalled = false
        
        let onKeyDown: () -> Void = {
            keyDownCalled = true
        }
        
        let onKeyUp: () -> Void = {
            keyUpCalled = true
        }
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
        
        XCTAssertTrue(result, "Push-to-talk hotkey registration should succeed")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
        
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "pushToTalk")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.mode, .pushToTalk)
        XCTAssertNotNil(config?.onKeyDown)
        XCTAssertNotNil(config?.onKeyUp)
    }
    
    func testPushToTalkKeyUp() {
        var keyDownCount = 0
        var keyUpCount = 0
        
        let onKeyDown: () -> Void = {
            keyDownCount += 1
        }
        
        let onKeyUp: () -> Void = {
            keyUpCount += 1
        }
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
        
        XCTAssertTrue(result, "Push-to-talk hotkey registration should succeed")
        
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "pushToTalk")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.mode, .pushToTalk)
    }
    
    func testToggleModeBackwardCompatibility() {
        var callbackInvoked = false
        
        let callback: () -> Void = {
            callbackInvoked = true
        }
        
        let config = HotkeyManager.HotkeyConfiguration(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )
        
        XCTAssertEqual(config.mode, .toggle)
        XCTAssertNotNil(config.onKeyDown)
        XCTAssertNil(config.onKeyUp)
    }
    
    func testPushToTalkModeConfiguration() {
        var keyDownCalled = false
        var keyUpCalled = false
        
        let onKeyDown: () -> Void = {
            keyDownCalled = true
        }
        
        let onKeyUp: () -> Void = {
            keyUpCalled = true
        }
        
        let config = HotkeyManager.HotkeyConfiguration(
            keyCode: 50,
            modifiers: [.command],
            identifier: "pushToTalk",
            mode: .pushToTalk,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
        
        XCTAssertEqual(config.mode, .pushToTalk)
        XCTAssertNotNil(config.onKeyDown)
        XCTAssertNotNil(config.onKeyUp)
        
        config.onKeyDown?()
        XCTAssertTrue(keyDownCalled)
        
        config.onKeyUp?()
        XCTAssertTrue(keyUpCalled)
    }
}
