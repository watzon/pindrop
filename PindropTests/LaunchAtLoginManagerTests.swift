//
//  LaunchAtLoginManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-29.
//

import XCTest
import ServiceManagement
@testable import Pindrop

private enum MockLaunchAtLoginFailure: Error {
    case failed
}

final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var status: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    
    var sut: LaunchAtLoginManager!
    var mockService: MockLaunchAtLoginService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        mockService = MockLaunchAtLoginService()
        sut = LaunchAtLoginManager(service: mockService)
    }
    
    override func tearDownWithError() throws {
        sut = nil
        mockService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() throws {
        XCTAssertNotNil(sut, "LaunchAtLoginManager should initialize successfully")
    }
    
    func testIsEnabledReflectsServiceStatus() throws {
        mockService.status = .enabled
        XCTAssertTrue(sut.isEnabled)

        mockService.status = .notRegistered
        XCTAssertFalse(sut.isEnabled)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testSetEnabledTrueRegistersService() throws {
        try sut.setEnabled(true)

        XCTAssertEqual(mockService.registerCallCount, 1)
        XCTAssertEqual(mockService.unregisterCallCount, 0)
        XCTAssertTrue(sut.isEnabled)
    }
    
    func testSetEnabledFalseUnregistersService() throws {
        mockService.status = .enabled

        try sut.setEnabled(false)

        XCTAssertEqual(mockService.unregisterCallCount, 1)
        XCTAssertEqual(mockService.registerCallCount, 0)
        XCTAssertFalse(sut.isEnabled)
    }
    
    func testToggleState() throws {
        XCTAssertFalse(sut.isEnabled)

        try sut.setEnabled(true)
        XCTAssertTrue(sut.isEnabled)

        try sut.setEnabled(false)
        XCTAssertFalse(sut.isEnabled)
    }

    func testSetEnabledTrueWrapsRegistrationFailure() throws {
        mockService.registerError = MockLaunchAtLoginFailure.failed

        XCTAssertThrowsError(try sut.setEnabled(true)) { error in
            guard case LaunchAtLoginManager.LaunchAtLoginError.registrationFailed = error else {
                XCTFail("Expected registrationFailed error")
                return
            }
        }
    }

    func testSetEnabledFalseWrapsUnregistrationFailure() throws {
        mockService.status = .enabled
        mockService.unregisterError = MockLaunchAtLoginFailure.failed

        XCTAssertThrowsError(try sut.setEnabled(false)) { error in
            guard case LaunchAtLoginManager.LaunchAtLoginError.unregistrationFailed = error else {
                XCTFail("Expected unregistrationFailed error")
                return
            }
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
        for i in 0..<3 {
            try sut.setEnabled(i.isMultiple(of: 2))
        }

        XCTAssertTrue(sut.isEnabled)
        XCTAssertEqual(mockService.registerCallCount, 2)
        XCTAssertEqual(mockService.unregisterCallCount, 1)
    }
}
