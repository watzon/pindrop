//
//  LaunchAtLoginManager.swift
//  Pindrop
//
//  Created on 2026-01-27.
//

import Foundation
import ServiceManagement
import os.log

protocol LaunchAtLoginServiceProtocol {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

struct MainAppLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LaunchAtLoginManager {

    private let service: LaunchAtLoginServiceProtocol
    
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
        service.status == .enabled
    }

    init(service: LaunchAtLoginServiceProtocol = MainAppLaunchAtLoginService()) {
        self.service = service
    }
    
    // MARK: - Methods
    
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try service.register()
                Log.app.info("Enabled launch at login")
            } catch {
                Log.app.error("Failed to enable launch at login: \(error.localizedDescription)")
                throw LaunchAtLoginError.registrationFailed(error)
            }
        } else {
            do {
                try service.unregister()
                Log.app.info("Disabled launch at login")
            } catch {
                Log.app.error("Failed to disable launch at login: \(error.localizedDescription)")
                throw LaunchAtLoginError.unregistrationFailed(error)
            }
        }
    }
}
