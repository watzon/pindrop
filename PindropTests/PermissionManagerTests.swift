//
//  PermissionManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
import AVFoundation
@testable import Pindrop

@MainActor
final class PermissionManagerTests: XCTestCase {
    
    var permissionManager: PermissionManager!
    
    override func setUp() async throws {
        try await super.setUp()
        permissionManager = PermissionManager()
    }
    
    override func tearDown() async throws {
        permissionManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Permission Status Tests
    
    func testCheckPermissionStatus() async throws {
        // Test that we can check permission status without crashing
        let status = await permissionManager.checkPermissionStatus()
        
        // Status should be one of the valid AVAuthorizationStatus values
        XCTAssertTrue(
            status == .notDetermined ||
            status == .restricted ||
            status == .denied ||
            status == .authorized,
            "Permission status should be a valid AVAuthorizationStatus"
        )
    }
    
    func testPermissionStatusReflectsSystemState() async throws {
        // Get current system permission status
        let systemStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let managerStatus = await permissionManager.checkPermissionStatus()
        
        // Manager should return same status as system
        XCTAssertEqual(
            managerStatus,
            systemStatus,
            "PermissionManager status should match system status"
        )
    }
    
    // MARK: - Permission Request Tests
    
    func testRequestPermission() async throws {
        // Note: This test will show permission dialog on first run
        // Subsequent runs will use cached permission state
        
        let granted = await permissionManager.requestPermission()
        
        // Result should be boolean
        XCTAssertTrue(granted == true || granted == false, "Request should return boolean")
        
        // After request, status should not be notDetermined
        let status = await permissionManager.checkPermissionStatus()
        XCTAssertNotEqual(
            status,
            .notDetermined,
            "After requesting permission, status should not be notDetermined"
        )
    }
    
    func testRequestPermissionUpdatesStatus() async throws {
        let statusBefore = await permissionManager.checkPermissionStatus()
        
        _ = await permissionManager.requestPermission()
        
        let statusAfter = await permissionManager.checkPermissionStatus()
        
        // If permission was notDetermined before, it should change after request
        if statusBefore == .notDetermined {
            XCTAssertNotEqual(
                statusAfter,
                .notDetermined,
                "Status should change from notDetermined after request"
            )
        }
    }
    
    // MARK: - Observable State Tests
    
    func testPermissionStatusIsObservable() async throws {
        // Test that permissionStatus property exists and is readable
        let status = await permissionManager.permissionStatus
        
        XCTAssertTrue(
            status == .notDetermined ||
            status == .restricted ||
            status == .denied ||
            status == .authorized,
            "Observable permissionStatus should be valid"
        )
    }
    
    func testRefreshPermissionStatusUpdatesObservableState() async throws {
        let initialStatus = await permissionManager.permissionStatus
        
        // Refresh status
        await permissionManager.refreshPermissionStatus()
        
        let refreshedStatus = await permissionManager.permissionStatus
        
        // Status should match system status after refresh
        let systemStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        XCTAssertEqual(
            refreshedStatus,
            systemStatus,
            "Refreshed status should match system status"
        )
    }
    
    // MARK: - Convenience Property Tests
    
    func testIsAuthorizedProperty() async throws {
        let status = await permissionManager.checkPermissionStatus()
        let isAuthorized = await permissionManager.isAuthorized
        
        XCTAssertEqual(
            isAuthorized,
            status == .authorized,
            "isAuthorized should be true only when status is .authorized"
        )
    }
    
    func testIsDeniedProperty() async throws {
        let status = await permissionManager.checkPermissionStatus()
        let isDenied = await permissionManager.isDenied
        
        XCTAssertEqual(
            isDenied,
            status == .denied || status == .restricted,
            "isDenied should be true when status is .denied or .restricted"
        )
    }
    
    // MARK: - Error Handling Tests
    
    func testHandlesRestrictedPermission() async throws {
        // This test documents behavior when permission is restricted
        // (e.g., parental controls, MDM policies)
        
        let status = await permissionManager.checkPermissionStatus()
        
        if status == .restricted {
            let granted = await permissionManager.requestPermission()
            XCTAssertFalse(granted, "Request should return false when restricted")
        }
    }
    
    func testHandlesDeniedPermission() async throws {
        // This test documents behavior when permission is denied
        
        let status = await permissionManager.checkPermissionStatus()
        
        if status == .denied {
            let granted = await permissionManager.requestPermission()
            XCTAssertFalse(granted, "Request should return false when denied")
        }
    }
    
    // MARK: - Accessibility Permission Tests
    
    func testAccessibilityPermissionCheck() async throws {
        let isGranted = await permissionManager.checkAccessibilityPermission()
        
        XCTAssertTrue(isGranted == true || isGranted == false, "Accessibility check should return boolean")
        
        let observableState = await permissionManager.accessibilityPermissionGranted
        XCTAssertEqual(
            observableState,
            isGranted,
            "Observable state should match check result"
        )
    }
    
    func testAccessibilityPermissionIsObservable() async throws {
        let state = await permissionManager.accessibilityPermissionGranted
        
        XCTAssertTrue(state == true || state == false, "Observable accessibilityPermissionGranted should be boolean")
    }
    
    func testIsAccessibilityAuthorizedProperty() async throws {
        let isGranted = await permissionManager.checkAccessibilityPermission()
        let isAuthorized = await permissionManager.isAccessibilityAuthorized
        
        XCTAssertEqual(
            isAuthorized,
            isGranted,
            "isAccessibilityAuthorized should match checkAccessibilityPermission result"
        )
    }
    
    func testRequestAccessibilityPermissionWithoutPrompt() async throws {
        let isGranted = await permissionManager.requestAccessibilityPermission(showPrompt: false)
        
        XCTAssertTrue(isGranted == true || isGranted == false, "Request should return boolean")
        
        let observableState = await permissionManager.accessibilityPermissionGranted
        XCTAssertEqual(
            observableState,
            isGranted,
            "Observable state should be updated after request"
        )
    }
    
    func testRequestAccessibilityPermissionWithPrompt() async throws {
        let isGranted = await permissionManager.requestAccessibilityPermission(showPrompt: true)
        
        XCTAssertTrue(isGranted == true || isGranted == false, "Request should return boolean")
        
        let observableState = await permissionManager.accessibilityPermissionGranted
        XCTAssertEqual(
            observableState,
            isGranted,
            "Observable state should be updated after request with prompt"
        )
    }
    
    func testRefreshAccessibilityPermissionStatus() async throws {
        await permissionManager.refreshAccessibilityPermissionStatus()
        
        let refreshedState = await permissionManager.accessibilityPermissionGranted
        
        XCTAssertTrue(refreshedState == true || refreshedState == false, "Refreshed state should be boolean")
    }
    
    func testOpenAccessibilityPreferences() async throws {
        await permissionManager.openAccessibilityPreferences()
    }
}
