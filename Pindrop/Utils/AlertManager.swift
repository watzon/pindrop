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
    
    func showModelLoadErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Model Loading Failed"
        alert.informativeText = "Failed to switch model: \(error.localizedDescription)"
        alert.alertStyle = .warning
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
    
    func showAIEnhancementErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "AI Enhancement Failed"
        
        let errorDescription = error.localizedDescription
        
        if errorDescription.contains("401") || errorDescription.contains("unauthorized") {
            alert.informativeText = """
                Your API key appears to be invalid or expired.
                
                To fix this:
                1. Open Settings → AI Enhancement
                2. Verify your API key is correct
                3. Check that your API endpoint is correct
                
                The transcription was saved without enhancement.
                """
        } else if errorDescription.contains("429") || errorDescription.contains("rate limit") {
            alert.informativeText = """
                You've exceeded your API rate limit or quota.
                
                To fix this:
                1. Wait a few minutes and try again
                2. Check your API provider's usage limits
                3. Consider upgrading your API plan
                
                The transcription was saved without enhancement.
                """
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            alert.informativeText = """
                Unable to connect to the AI enhancement service.
                
                Please check:
                1. Your internet connection
                2. The API endpoint URL is correct
                3. The service is not experiencing an outage
                
                The transcription was saved without enhancement.
                """
        } else {
            alert.informativeText = """
                An error occurred while enhancing your transcription:
                
                \(errorDescription)
                
                The original transcription was saved without enhancement.
                You can try enabling AI enhancement again in Settings.
                """
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        
        _ = alert.runModal()
    }
    
    func showGenericErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }

    func showHotkeyConflictAlert(hotkey: String, firstAction: String, secondAction: String) {
        let alert = NSAlert()
        alert.messageText = "Hotkey Conflict"
        alert.informativeText = "\(hotkey) is assigned to both \(firstAction) and \(secondAction). Only the first action will be active. Update your hotkeys in Settings to resolve this conflict."
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
