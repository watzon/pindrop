import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    
    private let audioRecorder: AudioRecorder
    private let settingsStore: SettingsStore
    
    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    
    init(audioRecorder: AudioRecorder, settingsStore: SettingsStore) {
        self.audioRecorder = audioRecorder
        self.settingsStore = settingsStore
        setupStatusItem()
        setupMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
            button.image?.isTemplate = true
        }
        
        statusItem?.menu = menu
    }
    
    private func setupMenu() {
        menu.removeAllItems()
        
        recordingStatusItem = NSMenuItem(title: "● Ready", action: nil, keyEquivalent: "")
        recordingStatusItem?.isEnabled = false
        menu.addItem(recordingStatusItem!)
        
        toggleRecordingItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        toggleRecordingItem?.target = self
        menu.addItem(toggleRecordingItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let historyItem = NSMenuItem(
            title: "History...",
            action: #selector(openHistory),
            keyEquivalent: "h"
        )
        historyItem.target = self
        menu.addItem(historyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Pindrop",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        updateMenuState()
    }
    
    @objc private func toggleRecording() {
        Task {
            do {
                if audioRecorder.isRecording {
                    _ = try await audioRecorder.stopRecording()
                } else {
                    try await audioRecorder.startRecording()
                }
                updateMenuState()
            } catch {
                print("Recording error: \(error)")
            }
        }
    }
    
    @objc private func openSettings() {
        print("Open Settings")
    }
    
    @objc private func openHistory() {
        print("Open History")
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateMenuState() {
        if audioRecorder.isRecording {
            recordingStatusItem?.title = "🔴 Recording"
            toggleRecordingItem?.title = "Stop Recording"
            
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            }
        } else {
            recordingStatusItem?.title = "● Ready"
            toggleRecordingItem?.title = "Start Recording"
            
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
            }
        }
    }
}
