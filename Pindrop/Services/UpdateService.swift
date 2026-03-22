//
//  UpdateService.swift
//  Pindrop
//
//  Created on 2026-02-02.
//

import Foundation
import Sparkle

@MainActor
protocol UpdateControlling: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

@MainActor
final class SparkleUpdateController: UpdateControlling {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }
}

/// Service for managing OTA updates via Sparkle framework.
/// Wraps SPUStandardUpdaterController for programmatic update control.
@MainActor
@Observable
class UpdateService: NSObject {
    
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
    
    private let timeoutScheduler: TaskScheduling
    private let checkTimeout: TimeInterval
    private var resetStateTask: ScheduledTask?
    private var updateController: UpdateControlling?
    
    /// Whether Sparkle is configured to automatically check for updates
    var automaticallyChecksForUpdates: Bool {
        get {
            updateController?.automaticallyChecksForUpdates ?? false
        }
        set {
            updateController?.automaticallyChecksForUpdates = newValue
            Log.app.info("Automatic update checks \(newValue ? "enabled" : "disabled")")
        }
    }
    
    /// Whether an update check can currently be performed
    var canCheckForUpdates: Bool {
        updateController?.canCheckForUpdates ?? false
    }
    
    /// The last time an update check was performed
    var lastUpdateCheckDate: Date? {
        updateController?.lastUpdateCheckDate
    }
    
    // MARK: - Initialization
    
    init(
        updateController: UpdateControlling? = nil,
        timeoutScheduler: TaskScheduling = DefaultTaskScheduler(),
        checkTimeout: TimeInterval = 3.0
    ) {
        self.timeoutScheduler = timeoutScheduler
        self.checkTimeout = checkTimeout
        super.init()

        self.updateController = updateController ?? Self.makeDefaultController()

        if self.updateController == nil {
            Log.app.debug("UpdateService initialized in test mode (Sparkle disabled)")
        } else {
            Log.app.info("UpdateService initialized with Sparkle")
        }
    }

    private static func makeDefaultController() -> UpdateControlling? {
        guard !AppTestMode.isRunningAnyTests else { return nil }
        return SparkleUpdateController()
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
        guard let controller = updateController else {
            Log.app.error("Cannot check for updates: updater not initialized")
            error = UpdateError.updaterNotInitialized
            state = .error
            return
        }
        
        guard controller.canCheckForUpdates else {
            Log.app.warning("Cannot check for updates: check already in progress or not allowed")
            return
        }
        
        Log.app.info("Checking for updates...")
        error = nil
        state = .checking
        resetStateTask?.cancel()
        
        controller.checkForUpdates()

        resetStateTask = timeoutScheduler.schedule(after: checkTimeout) { [weak self] in
            guard let self else { return }
            if state == .checking {
                state = .idle
            }
        }
    }
    
    /// Check for updates in background without showing UI unless an update is found.
    func checkForUpdatesInBackground() {
        guard let controller = updateController else {
            Log.app.error("Cannot check for updates: updater not initialized")
            return
        }
        
        guard controller.canCheckForUpdates else {
            Log.app.debug("Background update check skipped: not allowed at this time")
            return
        }
        
        Log.app.info("Checking for updates in background...")
        controller.checkForUpdatesInBackground()
    }
}
