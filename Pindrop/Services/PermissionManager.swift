//
//  PermissionManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class PermissionManager {
    
    private(set) var permissionStatus: AVAuthorizationStatus
    
    var isAuthorized: Bool {
        permissionStatus == .authorized
    }
    
    var isDenied: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }
    
    init() {
        self.permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
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
    
    func refreshPermissionStatus() {
        permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}
