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
import Observation

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
    
    init() {
        self.permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.accessibilityPermissionGranted = AXIsProcessTrusted()
    }
    
    // MARK: - Microphone Permission Methods
    
    func checkPermissionStatus() -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionStatus = status
        return status
    }
    
    func requestPermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        await refreshPermissionStatus()
        
        return granted
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
}
