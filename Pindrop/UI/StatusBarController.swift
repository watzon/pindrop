import AppKit
import SwiftUI
import SwiftData
import os.log

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
    private var modelContainer: ModelContainer?
    
    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    
    var onToggleRecording: (() async -> Void)?
    
    private var currentState: RecordingState = .idle {
        didSet {
            updateStatusBarIcon()
            updateMenuState()
        }
    }
    
    init(audioRecorder: AudioRecorder, settingsStore: SettingsStore) {
        self.audioRecorder = audioRecorder
        self.settingsStore = settingsStore
        setupStatusItem()
        setupMenu()
    }
    
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
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
            await onToggleRecording?()
        }
    }
    
    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsWindow()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Pindrop Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 550, height: 450))
            window.center()
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func openHistory() {
        guard let container = modelContainer else {
            Log.ui.error("ModelContainer not set - cannot open History")
            return
        }
        
        if historyWindow == nil {
            let historyView = HistoryWindow()
                .modelContainer(container)
            let hostingController = NSHostingController(rootView: historyView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Transcription History"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 700, height: 500))
            window.minSize = NSSize(width: 600, height: 400)
            window.center()
            
            historyWindow = window
        }
        
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateMenuState() {
        switch currentState {
        case .recording:
            recordingStatusItem?.title = "🔴 Recording"
            toggleRecordingItem?.title = "Stop Recording"
        case .processing:
            recordingStatusItem?.title = "⏳ Processing"
            toggleRecordingItem?.title = "Processing..."
            toggleRecordingItem?.isEnabled = false
        case .idle:
            recordingStatusItem?.title = "● Ready"
            toggleRecordingItem?.title = "Start Recording"
            toggleRecordingItem?.isEnabled = true
        }
    }
    
    func setRecordingState() {
        currentState = .recording
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        button.layer?.removeAllAnimations()
        
        switch currentState {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            button.alphaValue = 1.0
            
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
            button.alphaValue = 1.0
            
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.4
            animation.duration = 0.6
            animation.autoreverses = true
            animation.repeatCount = .infinity
            button.layer?.add(animation, forKey: "pulse")
            
        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")
            button.image?.isTemplate = false
            button.contentTintColor = .systemBlue
            button.alphaValue = 1.0
            
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.5
            animation.duration = 0.4
            animation.autoreverses = true
            animation.repeatCount = .infinity
            button.layer?.add(animation, forKey: "pulse")
        }
    }
    
    func setProcessingState() {
        currentState = .processing
    }
    
    func setIdleState() {
        currentState = .idle
    }
}
