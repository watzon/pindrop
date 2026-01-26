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
    private var mainWindowController: MainWindowController?
    
    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    
    private var settingsWindow: NSWindow?
    private var welcomePopover: NSPopover?
    
    var onToggleRecording: (() async -> Void)?
    var onOpenMainWindow: (() -> Void)?
    
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
    
    func setMainWindowController(_ controller: MainWindowController) {
        self.mainWindowController = controller
    }
    
    func showSettings() {
        openSettings()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let customIcon = NSImage(named: "PindropIcon") {
                let targetHeight: CGFloat = 18
                let aspectRatio: CGFloat = 1364.0 / 2000.0
                let targetWidth = targetHeight * aspectRatio
                
                let resizedIcon = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
                resizedIcon.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                customIcon.draw(
                    in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
                    from: NSRect(origin: .zero, size: customIcon.size),
                    operation: .copy,
                    fraction: 1.0
                )
                resizedIcon.unlockFocus()
                resizedIcon.isTemplate = true
                
                button.image = resizedIcon
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
                button.image?.isTemplate = true
            }
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
        
        let openWindowItem = NSMenuItem(
            title: "Open Pindrop",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)
        
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 750, height: 550))
            window.minSize = NSSize(width: 650, height: 450)
            window.center()
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func openMainWindow() {
        mainWindowController?.show()
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
    
    func showWelcomePopover() {
        guard let button = statusItem?.button else { return }
        
        if welcomePopover == nil {
            let popover = NSPopover()
            popover.contentViewController = NSHostingController(rootView: WelcomePopoverView {
                self.welcomePopover?.performClose(nil)
            })
            popover.behavior = .transient
            popover.animates = true
            welcomePopover = popover
        }
        
        welcomePopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

struct WelcomePopoverView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconView(icon: .hand, size: 24)
                    .foregroundStyle(.yellow)
                
                Text("You're all set!")
                    .font(.headline)
            }
            
            Text("Click this icon anytime to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                popoverItem(icon: .record, text: "Start/stop recording")
                popoverItem(icon: .settings, text: "Open settings")
                popoverItem(icon: .clock, text: "View transcription history")
            }
            
            Divider()
            
            HStack {
                Text("Or just use your hotkey!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
    
    private func popoverItem(icon: Icon, text: String) -> some View {
        HStack(spacing: 8) {
            IconView(icon: icon, size: 12)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            
            Text(text)
                .font(.subheadline)
        }
    }
}
