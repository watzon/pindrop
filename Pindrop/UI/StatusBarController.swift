import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    
    enum RecordingState {
        case idle
        case recording
        case processing
    }
    
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    
    private let audioRecorder: AudioRecorder
    private let settingsStore: SettingsStore
    
    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    
    private var currentState: RecordingState = .idle {
        didSet {
            updateStatusBarIcon()
        }
    }
    
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
            currentState = .recording
        } else {
            recordingStatusItem?.title = "● Ready"
            toggleRecordingItem?.title = "Start Recording"
            currentState = .idle
        }
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        switch currentState {
        case .idle:
            // Normal mic icon, monochrome (template)
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            
        case .recording:
            // Red mic icon with animation
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
            
            // Pulse animation
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.3
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            button.layer?.add(animation, forKey: "pulse")
            
        case .processing:
            // Waveform icon with animation
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Processing")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            
            // Rotation animation
            let animation = CABasicAnimation(keyPath: "transform.rotation")
            animation.fromValue = 0
            animation.toValue = Double.pi * 2
            animation.duration = 2.0
            animation.repeatCount = .infinity
            button.layer?.add(animation, forKey: "rotation")
        }
    }
    
    func setProcessingState() {
        currentState = .processing
    }
    
    func setIdleState() {
        currentState = .idle
    }
}
