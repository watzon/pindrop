//
//  PermissionManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics
import Observation

/// Protocol for permission checking, enabling mock-based testing.
protocol PermissionProviding: AnyObject {
    func requestPermission() async -> Bool
}

extension PermissionManager: PermissionProviding {}

@MainActor
@Observable
final class PermissionManager {
    
    // MARK: - Microphone Permission
    
    private(set) var permissionStatus: AVAuthorizationStatus
    
    var isAuthorized: Bool {
        permissionStatus == .authorized
    }
    
    var isDenied: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }
    
    // MARK: - Accessibility Permission

    private(set) var accessibilityPermissionGranted: Bool

    var isAccessibilityAuthorized: Bool {
        accessibilityPermissionGranted
    }

    // MARK: - Screen Recording Permission

    private(set) var screenRecordingPermissionGranted: Bool = false

    var isScreenRecordingAuthorized: Bool {
        screenRecordingPermissionGranted
    }
    
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    init() {
        if Self.isPreview {
            self.permissionStatus = .notDetermined
            self.accessibilityPermissionGranted = false
        } else {
            self.permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            self.accessibilityPermissionGranted = AXIsProcessTrusted()
        }
    }
    
    // MARK: - Microphone Permission Methods
    
    func checkPermissionStatus() -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionStatus = status
        return status
    }
    
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionStatus = status

        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }

            await refreshPermissionStatus()

            return granted
        @unknown default:
            return false
        }
    }
    
    func refreshPermissionStatus() async {
        permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    // MARK: - Accessibility Permission Methods
    
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        accessibilityPermissionGranted = trusted
        return trusted
    }
    
    func requestAccessibilityPermission(showPrompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showPrompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityPermissionGranted = trusted
        return trusted
    }
    
    func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionGranted = AXIsProcessTrusted()
    }
    
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Screen Recording Permission Methods

    func checkScreenRecordingPermission() -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        screenRecordingPermissionGranted = granted
        return granted
    }

    func requestScreenRecordingPermission() {
        let granted = CGRequestScreenCaptureAccess()
        screenRecordingPermissionGranted = granted
    }

    func openScreenRecordingPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
