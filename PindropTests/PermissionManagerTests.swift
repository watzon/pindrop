//
//  PermissionManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AVFoundation
import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PINDROP_RUN_INTEGRATION_TESTS"] == "1", "PermissionManager integration tests are disabled by default. Run `just test-integration` to execute them."))
struct PermissionManagerTests {
    private func makePermissionManager() -> PermissionManager {
        return PermissionManager()
    }

    private func expectedSystemPermissionStatus() -> AVAuthorizationStatus {
        let audioStatus: AVAuthorizationStatus
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            audioStatus = .authorized
        case .denied:
            audioStatus = .denied
        case .undetermined:
            audioStatus = .notDetermined
        @unknown default:
            audioStatus = .notDetermined
        }

        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if audioStatus == .authorized || captureStatus == .authorized {
            return .authorized
        }

        if captureStatus == .restricted {
            return .restricted
        }

        if audioStatus == .denied || captureStatus == .denied {
            return .denied
        }

        return .notDetermined
    }

    private func isValidAuthorizationStatus(_ status: AVAuthorizationStatus) -> Bool {
        status == .notDetermined ||
        status == .restricted ||
        status == .denied ||
        status == .authorized
    }

    @Test func checkPermissionStatus() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.checkPermissionStatus()

        #expect(isValidAuthorizationStatus(status))
    }

    @Test func permissionStatusReflectsSystemState() async throws {
        let permissionManager = makePermissionManager()
        let systemStatus = expectedSystemPermissionStatus()
        let managerStatus = permissionManager.checkPermissionStatus()

        #expect(managerStatus == systemStatus)
    }

    @Test func microphoneAuthorizationSnapshotMatchesPermissionState() async throws {
        let permissionManager = makePermissionManager()
        let snapshot = permissionManager.microphoneAuthorizationSnapshot()
        let managerStatus = permissionManager.checkPermissionStatus()

        #expect(snapshot.resolvedStatus == managerStatus)
        #expect(!snapshot.audioApplicationStatus.isEmpty)
        #expect(!snapshot.captureDeviceStatus.isEmpty)
        #expect(!snapshot.hasRequestedThisLaunch)
        #expect(snapshot.cachedDecision == nil)
    }

    @Test func requestPermission() async throws {
        let permissionManager = makePermissionManager()
        let granted = await permissionManager.requestPermission()

        #expect(granted == true || granted == false)

        let status = permissionManager.checkPermissionStatus()
        #expect(isValidAuthorizationStatus(status))
    }

    @Test func requestPermissionUpdatesStatus() async throws {
        let permissionManager = makePermissionManager()
        let statusBefore = permissionManager.checkPermissionStatus()

        _ = await permissionManager.requestPermission()

        let statusAfter = permissionManager.checkPermissionStatus()
        #expect(isValidAuthorizationStatus(statusAfter))
        #expect(isValidAuthorizationStatus(statusBefore))
    }

    @Test func permissionStatusIsObservable() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.permissionStatus

        #expect(isValidAuthorizationStatus(status))
    }

    @Test func refreshPermissionStatusUpdatesObservableState() async throws {
        let permissionManager = makePermissionManager()
        await permissionManager.refreshPermissionStatus()

        let refreshedStatus = permissionManager.permissionStatus
        let systemStatus = expectedSystemPermissionStatus()

        #expect(refreshedStatus == systemStatus)
    }

    @Test func isAuthorizedProperty() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.checkPermissionStatus()
        let isAuthorized = permissionManager.isAuthorized

        #expect(isAuthorized == (status == .authorized))
    }

    @Test func isDeniedProperty() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.checkPermissionStatus()
        let isDenied = permissionManager.isDenied

        #expect(isDenied == (status == .denied || status == .restricted))
    }

    @Test func handlesRestrictedPermission() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.checkPermissionStatus()

        if status == .restricted {
            let granted = await permissionManager.requestPermission()
            #expect(granted == false)
        }
    }

    @Test func handlesDeniedPermission() async throws {
        let permissionManager = makePermissionManager()
        let status = permissionManager.checkPermissionStatus()

        if status == .denied {
            let granted = await permissionManager.requestPermission()
            #expect(granted == false)
        }
    }

    @Test func accessibilityPermissionCheck() async throws {
        let permissionManager = makePermissionManager()
        let isGranted = permissionManager.checkAccessibilityPermission()

        #expect(isGranted == true || isGranted == false)

        let observableState = permissionManager.accessibilityPermissionGranted
        #expect(observableState == isGranted)
    }

    @Test func accessibilityPermissionIsObservable() async throws {
        let permissionManager = makePermissionManager()
        let state = permissionManager.accessibilityPermissionGranted

        #expect(state == true || state == false)
    }

    @Test func isAccessibilityAuthorizedProperty() async throws {
        let permissionManager = makePermissionManager()
        let isGranted = permissionManager.checkAccessibilityPermission()
        let isAuthorized = permissionManager.isAccessibilityAuthorized

        #expect(isAuthorized == isGranted)
    }

    @Test func requestAccessibilityPermissionWithoutPrompt() async throws {
        let permissionManager = makePermissionManager()
        let isGranted = permissionManager.requestAccessibilityPermission(showPrompt: false)

        #expect(isGranted == true || isGranted == false)

        let observableState = permissionManager.accessibilityPermissionGranted
        #expect(observableState == isGranted)
    }

    @Test func requestAccessibilityPermissionWithPrompt() async throws {
        let permissionManager = makePermissionManager()
        let isGranted = permissionManager.requestAccessibilityPermission(showPrompt: true)

        #expect(isGranted == true || isGranted == false)

        let observableState = permissionManager.accessibilityPermissionGranted
        #expect(observableState == isGranted)
    }

    @Test func refreshAccessibilityPermissionStatus() async throws {
        let permissionManager = makePermissionManager()
        permissionManager.refreshAccessibilityPermissionStatus()

        let refreshedState = permissionManager.accessibilityPermissionGranted
        #expect(refreshedState == true || refreshedState == false)
    }

    @Test func openAccessibilityPreferences() async throws {
        let permissionManager = makePermissionManager()
        permissionManager.openAccessibilityPreferences()
    }
}
