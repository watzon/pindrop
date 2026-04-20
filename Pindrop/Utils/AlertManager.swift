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

    private var locale: Locale {
        let rawValue = UserDefaults.standard.string(forKey: "selectedAppLocale") ?? AppLocale.automatic.rawValue
        return AppLocale(rawValue: rawValue)?.locale ?? .autoupdatingCurrent
    }
    
    func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = localized("Accessibility Permission Required", locale: locale)
        alert.informativeText = localized("""
            Pindrop needs Accessibility permission to insert text at your cursor.
            
            To grant permission:
            1. Click "Open System Settings" below
            2. Click the + button
            3. Navigate to the app shown in Finder
            4. Restart Pindrop after granting permission
            
            Without this permission, text will only be copied to your clipboard.
            """, locale: locale)
        alert.alertStyle = .informational
        alert.addButton(withTitle: localized("Open System Settings", locale: locale))
        alert.addButton(withTitle: localized("Show App in Finder", locale: locale))
        alert.addButton(withTitle: localized("Use Clipboard Only", locale: locale))
        
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
        alert.messageText = localized("Microphone Permission Required", locale: locale)
        alert.informativeText = localized("Pindrop needs microphone access to record and transcribe your voice.\n\nPlease grant permission in System Settings.", locale: locale)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("Open System Settings", locale: locale))
        alert.addButton(withTitle: localized("Cancel", locale: locale))
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }
    
    func showModelNotLoadedAlert() {
        let alert = NSAlert()
        alert.messageText = localized("No Model Loaded", locale: locale)
        alert.informativeText = localized("Please download a Whisper model in Settings before recording.\n\nGo to Settings → Models to download a model.", locale: locale)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("Open Settings", locale: locale))
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        _ = alert.runModal()
    }
    
    func showModelTimeoutAlert() {
        let alert = NSAlert()
        alert.messageText = localized("Model Loading Timed Out", locale: locale)
        alert.informativeText = localized("""
            The model failed to load within 60 seconds. This usually means the model files are corrupted or incompatible.
            
            To fix this:
            1. Open Settings → Models
            2. Delete the problematic model
            3. Re-download the model
            
            If the problem persists, try a smaller model (Tiny or Base).
            """, locale: locale)
        alert.alertStyle = .critical
        alert.addButton(withTitle: localized("Open Settings", locale: locale))
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        _ = alert.runModal()
    }
    
    func showModelLoadErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = localized("Model Loading Failed", locale: locale)
        alert.informativeText = String(format: localized("Failed to switch model: %@", locale: locale), error.localizedDescription)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        _ = alert.runModal()
    }
    
    func showTranscriptionErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = localized("Transcription Failed", locale: locale)
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        alert.runModal()
    }
    
    func showAIEnhancementErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = localized("AI Enhancement Failed", locale: locale)
        
        let errorDescription = error.localizedDescription
        
        if errorDescription.contains("401") || errorDescription.contains("unauthorized") {
            alert.informativeText = localized("""
                Your API key appears to be invalid or expired.
                
                To fix this:
                1. Open Settings → AI Enhancement
                2. Verify your API key is correct
                3. Check that your API endpoint is correct
                
                The transcription was saved without enhancement.
                """, locale: locale)
        } else if errorDescription.contains("429") || errorDescription.contains("rate limit") {
            alert.informativeText = localized("""
                You've exceeded your API rate limit or quota.
                
                To fix this:
                1. Wait a few minutes and try again
                2. Check your API provider's usage limits
                3. Consider upgrading your API plan
                
                The transcription was saved without enhancement.
                """, locale: locale)
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            alert.informativeText = localized("""
                Unable to connect to the AI enhancement service.
                
                Please check:
                1. Your internet connection
                2. The API endpoint URL is correct
                3. The service is not experiencing an outage
                
                The transcription was saved without enhancement.
                """, locale: locale)
        } else {
            alert.informativeText = String(
                format: localized("An error occurred while enhancing your transcription:\n\n%@\n\nThe original transcription was saved without enhancement.\nYou can try enabling AI enhancement again in Settings.", locale: locale),
                errorDescription
            )
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("Open Settings", locale: locale))
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        _ = alert.runModal()
    }
    
    func showGenericErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("OK", locale: locale))
        
        alert.runModal()
    }

    func showHotkeyConflictAlert(hotkey: String, firstAction: String, secondAction: String) {
        let alert = NSAlert()
        alert.messageText = localized("Hotkey Conflict", locale: locale)
        alert.informativeText = String(
            format: localized("%@ is assigned to both %@ and %@. Only the first action will be active. Update your hotkeys in Settings to resolve this conflict.", locale: locale),
            hotkey,
            firstAction,
            secondAction
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("OK", locale: locale))

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
