//
//  UpdateService.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import Foundation
import Sparkle
import os.log

/// Service for managing OTA updates via Sparkle framework.
/// Wraps SPUStandardUpdaterController for programmatic update control.
@MainActor
@Observable
class UpdateService: NSObject {

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["PINDROP_TEST_MODE"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    // MARK: - Types
    
    enum State: Equatable {
        case idle
        case checking
        case updateAvailable
        case error
    }
    
    enum UpdateError: Error, LocalizedError {
        case updaterNotInitialized
        case checkFailed(String)
        case updateInProgress
        
        var errorDescription: String? {
            switch self {
            case .updaterNotInitialized:
                return "Update service not initialized"
            case .checkFailed(let message):
                return "Update check failed: \(message)"
            case .updateInProgress:
                return "An update is already in progress"
            }
        }
    }
    
    // MARK: - Properties
    
    private(set) var state: State = .idle
    private(set) var error: Error?
    
    /// The Sparkle updater controller that manages update checks and UI
    private var updaterController: SPUStandardUpdaterController?
    
    /// Whether Sparkle is configured to automatically check for updates
    var automaticallyChecksForUpdates: Bool {
        get {
            updaterController?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            Log.app.info("Automatic update checks \(newValue ? "enabled" : "disabled")")
        }
    }
    
    /// Whether an update check can currently be performed
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }
    
    /// The last time an update check was performed
    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()

        if Self.isRunningTests {
            updaterController = nil
            Log.app.debug("UpdateService initialized in test mode (Sparkle disabled)")
        } else {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )

            Log.app.info("UpdateService initialized with Sparkle")
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if update should be deferred based on app state.
    /// Updates should not interrupt recording or transcription.
    ///
    /// - Parameter isRecording: Whether the app is currently recording
    /// - Returns: True if update should be deferred, false if safe to proceed
    func shouldDeferUpdate(isRecording: Bool) -> Bool {
        if isRecording {
            Log.app.debug("Update deferred: recording in progress")
            return true
        }
        return false
    }
    
    /// Manually trigger an update check.
    /// This will show Sparkle's standard update UI if an update is available.
    func checkForUpdates() {
        guard let controller = updaterController else {
            Log.app.error("Cannot check for updates: updater not initialized")
            error = UpdateError.updaterNotInitialized
            state = .error
            return
        }
        
        guard controller.updater.canCheckForUpdates else {
            Log.app.warning("Cannot check for updates: check already in progress or not allowed")
            return
        }
        
        Log.app.info("Checking for updates...")
        state = .checking
        
        controller.checkForUpdates(nil)
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            if state == .checking {
                state = .idle
            }
        }
    }
    
    /// Check for updates in background without showing UI unless an update is found.
    func checkForUpdatesInBackground() {
        guard let controller = updaterController else {
            Log.app.error("Cannot check for updates: updater not initialized")
            return
        }
        
        guard controller.updater.canCheckForUpdates else {
            Log.app.debug("Background update check skipped: not allowed at this time")
            return
        }
        
        Log.app.info("Checking for updates in background...")
        controller.updater.checkForUpdatesInBackground()
    }
}
