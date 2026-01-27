//
//  AlertManager.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import AppKit

@MainActor
final class AlertManager {
    
    static let shared = AlertManager()
    
    private init() {}
    
    func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Pindrop needs Accessibility permission to insert text at your cursor.
            
            To grant permission:
            1. Click "Open System Settings" below
            2. Click the + button
            3. Navigate to the app shown in Finder
            4. Restart Pindrop after granting permission
            
            Without this permission, text will only be copied to your clipboard.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Show App in Finder")
        alert.addButton(withTitle: "Use Clipboard Only")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        } else if response == .alertSecondButtonReturn {
            revealAppInFinder()
            openAccessibilitySettings()
        }
    }
    
    private func revealAppInFinder() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.selectFile(appURL.path, inFileViewerRootedAtPath: appURL.deletingLastPathComponent().path)
    }
    
    func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Pindrop needs microphone access to record and transcribe your voice.\n\nPlease grant permission in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }
    
    func showModelNotLoadedAlert() {
        let alert = NSAlert()
        alert.messageText = "No Model Loaded"
        alert.informativeText = "Please download a Whisper model in Settings before recording.\n\nGo to Settings → Models to download a model."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        
        _ = alert.runModal()
    }
    
    func showModelTimeoutAlert() {
        let alert = NSAlert()
        alert.messageText = "Model Loading Timed Out"
        alert.informativeText = """
            The model failed to load within 60 seconds. This usually means the model files are corrupted or incompatible.
            
            To fix this:
            1. Open Settings → Models
            2. Delete the problematic model
            3. Re-download the model
            
            If the problem persists, try a smaller model (Tiny or Base).
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        
        _ = alert.runModal()
    }
    
    func showTranscriptionErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Transcription Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }
    
    func showGenericErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
