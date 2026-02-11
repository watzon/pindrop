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

/// Protocol for permission checking, enabling mock-based testing.
protocol PermissionProviding: AnyObject {
    func requestPermission() async -> Bool
}

extension PermissionManager: PermissionProviding {}

@MainActor
@Observable
final class PermissionManager {

    struct MicrophoneAuthorizationSnapshot {
        let resolvedStatus: AVAuthorizationStatus
        let audioApplicationStatus: String
        let captureDeviceStatus: String
        let hasRequestedThisLaunch: Bool
        let cachedDecision: Bool?
    }
    
    // MARK: - Microphone Permission
    
    private(set) var permissionStatus: AVAuthorizationStatus
    private var pendingMicrophonePermissionRequest: Task<Bool, Never>?
    private var hasRequestedMicrophonePermissionThisLaunch = false
    private var cachedMicrophonePermissionDecision: Bool?
    
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

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static var shouldSuppressSystemPermissionPrompts: Bool {
        isPreview || isRunningTests
    }
    
    init() {
        if Self.isPreview {
            self.permissionStatus = .notDetermined
            self.accessibilityPermissionGranted = false
        } else {
            self.permissionStatus = Self.resolveMicrophonePermissionStatus(
                audioPermission: AVAudioApplication.shared.recordPermission,
                capturePermission: AVCaptureDevice.authorizationStatus(for: .audio)
            )
            self.accessibilityPermissionGranted = AXIsProcessTrusted()
        }
    }
    
    // MARK: - Microphone Permission Methods
    
    func checkPermissionStatus() -> AVAuthorizationStatus {
        let status = currentMicrophonePermissionStatus()

        if status == .notDetermined,
           hasRequestedMicrophonePermissionThisLaunch,
           let cachedDecision = cachedMicrophonePermissionDecision {
            permissionStatus = cachedDecision ? .authorized : .denied
            return permissionStatus
        }

        permissionStatus = status
        return status
    }
    
    func requestPermission() async -> Bool {
        let status = currentMicrophonePermissionStatus()
        permissionStatus = status

        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            if let pendingRequest = pendingMicrophonePermissionRequest {
                return await pendingRequest.value
            }

            if hasRequestedMicrophonePermissionThisLaunch,
               let cachedDecision = cachedMicrophonePermissionDecision {
                permissionStatus = cachedDecision ? .authorized : .denied
                return cachedDecision
            }

            hasRequestedMicrophonePermissionThisLaunch = true

            let requestTask = Task { () -> Bool in
                await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
            pendingMicrophonePermissionRequest = requestTask

            let granted = await requestTask.value
            pendingMicrophonePermissionRequest = nil
            cachedMicrophonePermissionDecision = granted

            await refreshPermissionStatus()

            if permissionStatus == .notDetermined {
                permissionStatus = granted ? .authorized : .denied
            }

            return granted
        @unknown default:
            return false
        }
    }
    
    func refreshPermissionStatus() async {
        let status = currentMicrophonePermissionStatus()

        if status == .notDetermined,
           hasRequestedMicrophonePermissionThisLaunch,
           let cachedDecision = cachedMicrophonePermissionDecision {
            permissionStatus = cachedDecision ? .authorized : .denied
            return
        }

        permissionStatus = status
    }

    func microphoneAuthorizationSnapshot() -> MicrophoneAuthorizationSnapshot {
        let audioStatus = AVAudioApplication.shared.recordPermission
        let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        return MicrophoneAuthorizationSnapshot(
            resolvedStatus: Self.resolveMicrophonePermissionStatus(
                audioPermission: audioStatus,
                capturePermission: captureStatus
            ),
            audioApplicationStatus: Self.describeAudioApplicationPermission(audioStatus),
            captureDeviceStatus: Self.describeCapturePermission(captureStatus),
            hasRequestedThisLaunch: hasRequestedMicrophonePermissionThisLaunch,
            cachedDecision: cachedMicrophonePermissionDecision
        )
    }

    private func currentMicrophonePermissionStatus() -> AVAuthorizationStatus {
        Self.resolveMicrophonePermissionStatus(
            audioPermission: AVAudioApplication.shared.recordPermission,
            capturePermission: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    private static func resolveMicrophonePermissionStatus(
        audioPermission: AVAudioApplication.recordPermission,
        capturePermission: AVAuthorizationStatus
    ) -> AVAuthorizationStatus {
        let audioStatus: AVAuthorizationStatus
        switch audioPermission {
        case .granted:
            audioStatus = .authorized
        case .denied:
            audioStatus = .denied
        case .undetermined:
            audioStatus = .notDetermined
        @unknown default:
            audioStatus = .notDetermined
        }

        if audioStatus == .authorized || capturePermission == .authorized {
            return .authorized
        }

        if capturePermission == .restricted {
            return .restricted
        }

        if audioStatus == .denied || capturePermission == .denied {
            return .denied
        }

        return .notDetermined
    }

    private static func describeAudioApplicationPermission(_ permission: AVAudioApplication.recordPermission) -> String {
        switch permission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            return "undetermined"
        @unknown default:
            return "unknown"
        }
    }

    private static func describeCapturePermission(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }
    
    // MARK: - Accessibility Permission Methods
    
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        accessibilityPermissionGranted = trusted
        return trusted
    }
    
    func requestAccessibilityPermission(showPrompt: Bool = true) -> Bool {
        let shouldPrompt = showPrompt && !Self.shouldSuppressSystemPermissionPrompts
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityPermissionGranted = trusted
        return trusted
    }
    
    func refreshAccessibilityPermissionStatus() {
        accessibilityPermissionGranted = AXIsProcessTrusted()
    }
    
    func openAccessibilityPreferences() {
        guard !Self.shouldSuppressSystemPermissionPrompts else { return }

        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

}
