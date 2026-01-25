//
//  HotkeyManagerTests.swift
//  PindropTests
//
//  Created on 1/25/26.
//

import XCTest
import Carbon
@testable import Pindrop

final class HotkeyManagerTests: XCTestCase {
    
    var hotkeyManager: HotkeyManager!
    
    override func setUp() {
        super.setUp()
        hotkeyManager = HotkeyManager()
    }
    
    override func tearDown() {
        hotkeyManager = nil
        super.tearDown()
    }
    
    // MARK: - Registration Tests
    
    func testRegisterHotkey() {
        let expectation = XCTestExpectation(description: "Hotkey registered successfully")
        var callbackInvoked = false
        
        let callback: () -> Void = {
            callbackInvoked = true
        }
        
        let result = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            onKeyDown: callback
        )
        
        XCTAssertTrue(result, "Hotkey registration should succeed")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should be registered")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
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
    }
    
    func testUnregisterNonexistentHotkey() {
        // When: Attempting to unregister a hotkey that doesn't exist
        let result = hotkeyManager.unregisterHotkey(identifier: "nonexistent")
        
        // Then: Unregistration should fail gracefully
        XCTAssertFalse(result, "Unregistering nonexistent hotkey should return false")
    }
    
    func testUnregisterAll() {
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(keyCode: 49, modifiers: [.option], identifier: "toggle", onKeyDown: callback)
        _ = hotkeyManager.registerHotkey(keyCode: 50, modifiers: [.command], identifier: "pushToTalk", onKeyDown: callback)
        
        hotkeyManager.unregisterAll()
        
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
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
        // When: Getting configuration for nonexistent hotkey
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "nonexistent")
        
        // Then: Should return nil
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
