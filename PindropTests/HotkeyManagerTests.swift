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
        // Given: A hotkey configuration for Option+Space
        let expectation = XCTestExpectation(description: "Hotkey registered successfully")
        var callbackInvoked = false
        
        let callback: () -> Void = {
            callbackInvoked = true
        }
        
        // When: Registering the hotkey
        let result = hotkeyManager.registerHotkey(
            keyCode: 49, // Space key
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )
        
        // Then: Registration should succeed
        XCTAssertTrue(result, "Hotkey registration should succeed")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"), "Hotkey should be registered")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRegisterMultipleHotkeys() {
        // Given: Two different hotkey configurations
        let callback1: () -> Void = {}
        let callback2: () -> Void = {}
        
        // When: Registering both hotkeys
        let result1 = hotkeyManager.registerHotkey(
            keyCode: 49, // Space
            modifiers: [.option],
            identifier: "toggle",
            callback: callback1
        )
        
        let result2 = hotkeyManager.registerHotkey(
            keyCode: 50, // Backtick
            modifiers: [.command, .shift],
            identifier: "pushToTalk",
            callback: callback2
        )
        
        // Then: Both should be registered
        XCTAssertTrue(result1, "First hotkey should register")
        XCTAssertTrue(result2, "Second hotkey should register")
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        XCTAssertTrue(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
    }
    
    func testRegisterDuplicateIdentifier() {
        // Given: A registered hotkey
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )
        
        // When: Attempting to register another hotkey with the same identifier
        let result = hotkeyManager.registerHotkey(
            keyCode: 50,
            modifiers: [.command],
            identifier: "toggle",
            callback: callback
        )
        
        // Then: Registration should fail
        XCTAssertFalse(result, "Duplicate identifier registration should fail")
    }
    
    // MARK: - Unregistration Tests
    
    func testUnregisterHotkey() {
        // Given: A registered hotkey
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )
        
        // When: Unregistering the hotkey
        let result = hotkeyManager.unregisterHotkey(identifier: "toggle")
        
        // Then: Unregistration should succeed
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
        // Given: Multiple registered hotkeys
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(keyCode: 49, modifiers: [.option], identifier: "toggle", callback: callback)
        _ = hotkeyManager.registerHotkey(keyCode: 50, modifiers: [.command], identifier: "pushToTalk", callback: callback)
        
        // When: Unregistering all hotkeys
        hotkeyManager.unregisterAll()
        
        // Then: No hotkeys should be registered
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "toggle"))
        XCTAssertFalse(hotkeyManager.isHotkeyRegistered(identifier: "pushToTalk"))
    }
    
    // MARK: - Configuration Tests
    
    func testGetHotkeyConfiguration() {
        // Given: A registered hotkey
        let callback: () -> Void = {}
        _ = hotkeyManager.registerHotkey(
            keyCode: 49,
            modifiers: [.option],
            identifier: "toggle",
            callback: callback
        )
        
        // When: Getting the configuration
        let config = hotkeyManager.getHotkeyConfiguration(identifier: "toggle")
        
        // Then: Configuration should match
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
}
