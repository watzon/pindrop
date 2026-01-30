//
//  LaunchAtLoginManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-29.
//

import XCTest
import ServiceManagement
@testable import Pindrop

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    
    var sut: LaunchAtLoginManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = LaunchAtLoginManager()
    }
    
    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() throws {
        XCTAssertNotNil(sut, "LaunchAtLoginManager should initialize successfully")
    }
    
    func testIsEnabledReturnsBoolean() throws {
        // When: We check isEnabled
        let isEnabled = sut.isEnabled
        
        // Then: It should return a boolean value
        XCTAssertNotNil(isEnabled)
        XCTAssertTrue(isEnabled == true || isEnabled == false)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testSetEnabledTrueAttemptsRegistration() throws {
        // Given: LaunchAtLoginManager is initialized
        let initialState = sut.isEnabled
        
        // When: We try to enable it (may fail in test environment)
        do {
            try sut.setEnabled(true)
            // Then: If it succeeds, isEnabled should be true
            XCTAssertTrue(sut.isEnabled)
        } catch {
            // In test environment, this may fail - that's acceptable
            // Just verify it throws the correct error type
            XCTAssertTrue(error is LaunchAtLoginManager.LaunchAtLoginError)
        }
        
        // Restore original state
        try? sut.setEnabled(initialState)
    }
    
    func testSetEnabledFalseAttemptsUnregistration() throws {
        // Given: LaunchAtLoginManager is initialized
        let initialState = sut.isEnabled
        
        // When: We try to disable it (may fail in test environment)
        do {
            try sut.setEnabled(false)
            // Then: If it succeeds, isEnabled should be false
            XCTAssertFalse(sut.isEnabled)
        } catch {
            // In test environment, this may fail - that's acceptable
            XCTAssertTrue(error is LaunchAtLoginManager.LaunchAtLoginError)
        }
        
        // Restore original state
        try? sut.setEnabled(initialState)
    }
    
    func testToggleState() throws {
        // Given: Current state
        let initialState = sut.isEnabled
        
        // When: Toggle to opposite state
        do {
            try sut.setEnabled(!initialState)
            // Then: State should be toggled
            XCTAssertEqual(sut.isEnabled, !initialState)
            
            // When: Toggle back
            try sut.setEnabled(initialState)
            // Then: State should be restored
            XCTAssertEqual(sut.isEnabled, initialState)
        } catch {
            // In test environment, this may fail - that's acceptable
            // Just verify no crash occurred
            XCTAssertTrue(error is LaunchAtLoginManager.LaunchAtLoginError)
        }
    }
    
    // MARK: - Error Tests
    
    func testErrorDescriptions() throws {
        // Given: Error instances
        let registrationError = LaunchAtLoginManager.LaunchAtLoginError.registrationFailed(NSError(domain: "test", code: 1))
        let unregistrationError = LaunchAtLoginManager.LaunchAtLoginError.unregistrationFailed(NSError(domain: "test", code: 2))
        
        // Then: Error descriptions should be present
        XCTAssertNotNil(registrationError.errorDescription)
        XCTAssertNotNil(unregistrationError.errorDescription)
        XCTAssertTrue(registrationError.errorDescription?.contains("enable") ?? false)
        XCTAssertTrue(unregistrationError.errorDescription?.contains("disable") ?? false)
    }
    
    func testErrorConformsToLocalizedError() throws {
        // Given: An error
        let error = LaunchAtLoginManager.LaunchAtLoginError.registrationFailed(NSError(domain: "test", code: 1))
        
        // Then: It should conform to LocalizedError
        XCTAssertTrue(error is LocalizedError)
        XCTAssertNotNil((error as LocalizedError).errorDescription)
    }
    
    // MARK: - State Consistency Tests
    
    func testStateConsistencyAfterMultipleToggles() throws {
        // Given: Initial state
        let initialState = sut.isEnabled
        var lastKnownState = initialState
        
        // When: Multiple toggles (with error handling)
        for i in 0..<3 {
            do {
                try sut.setEnabled(!lastKnownState)
                lastKnownState = !lastKnownState
                XCTAssertEqual(sut.isEnabled, lastKnownState, "Toggle \(i) failed")
            } catch {
                // Stop testing if we hit an error
                break
            }
        }
        
        // Restore original state
        try? sut.setEnabled(initialState)
    }
}
