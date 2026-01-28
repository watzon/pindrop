//
//  LaunchAtLoginManager.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import ServiceManagement
import os.log

@MainActor
final class LaunchAtLoginManager {
    
    // MARK: - Errors
    
    enum LaunchAtLoginError: Error, LocalizedError {
        case registrationFailed(Error)
        case unregistrationFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .registrationFailed(let error):
                return "Failed to enable launch at login: \(error.localizedDescription)"
            case .unregistrationFailed(let error):
                return "Failed to disable launch at login: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Properties
    
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    // MARK: - Methods
    
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                Log.app.info("Enabled launch at login")
            } catch {
                Log.app.error("Failed to enable launch at login: \(error.localizedDescription)")
                throw LaunchAtLoginError.registrationFailed(error)
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
                Log.app.info("Disabled launch at login")
            } catch {
                Log.app.error("Failed to disable launch at login: \(error.localizedDescription)")
                throw LaunchAtLoginError.unregistrationFailed(error)
            }
        }
    }
}
