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

    // MARK: - Menu Item References

    private var recordingStatusItem: NSMenuItem?
    private var toggleRecordingItem: NSMenuItem?
    private var clearAudioBufferItem: NSMenuItem?
    private var cancelOperationItem: NSMenuItem?

    private var transcriptsMenu: NSMenu?
    private var copyLastTranscriptItem: NSMenuItem?
    private var exportLastTranscriptItem: NSMenuItem?
    private var recentTranscriptsSeparator: NSMenuItem?

    private var outputModeItem: NSMenuItem?
    private var aiEnhancementItem: NSMenuItem?

    private var toggleFloatingIndicatorItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var openHistoryItem: NSMenuItem?

    private var modelMenu: NSMenu?
    private var currentModelItem: NSMenuItem?

    private var settingsWindow: NSWindow?
    private var welcomePopover: NSPopover?

    // MARK: - Callbacks

    var onToggleRecording: (() async -> Void)?
    var onOpenMainWindow: (() -> Void)?
    var onCopyLastTranscript: (() async -> Void)?
    var onExportLastTranscript: (() async -> Void)?
    var onClearAudioBuffer: (() async -> Void)?
    var onCancelOperation: (() async -> Void)?
    var onToggleOutputMode: (() -> Void)?
    var onToggleAIControlled: (() -> Void)?
    var onToggleFloatingIndicator: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onSelectModel: ((String) -> Void)?

    // Recent transcripts for submenu
    private(set) var recentTranscripts: [(id: UUID, text: String, timestamp: Date)] = []

    // MARK: - State

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

    func showSettings(tab: SettingsTab = .general) {
        openSettingsWindow(tab: tab)
    }

    func updateRecentTranscripts(_ transcripts: [(id: UUID, text: String, timestamp: Date)]) {
        self.recentTranscripts = Array(transcripts.prefix(5))
        updateRecentTranscriptsMenu()
    }

    func updateSelectedModel(_ modelName: String) {
        currentModelItem?.title = "Current: \(modelName.replacingOccurrences(of: "openai_whisper-", with: ""))"
    }

    // MARK: - Setup

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

        // === RECORDING SECTION ===
        let recordingHeader = createHeaderItem("Recording")
        menu.addItem(recordingHeader)

        recordingStatusItem = NSMenuItem(title: "● Ready", action: nil, keyEquivalent: "")
        recordingStatusItem?.isEnabled = false
        recordingStatusItem?.attributedTitle = NSAttributedString(
            string: "● Ready",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(recordingStatusItem!)

        toggleRecordingItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        toggleRecordingItem?.target = self
        menu.addItem(toggleRecordingItem!)

        clearAudioBufferItem = NSMenuItem(
            title: "Clear Audio Buffer",
            action: #selector(clearAudioBuffer),
            keyEquivalent: "x"
        )
        clearAudioBufferItem?.target = self
        clearAudioBufferItem?.isEnabled = false
        menu.addItem(clearAudioBufferItem!)

        cancelOperationItem = NSMenuItem(
            title: "Cancel Operation",
            action: #selector(cancelOperation),
            keyEquivalent: ""
        )
        cancelOperationItem?.target = self
        cancelOperationItem?.isEnabled = false
        menu.addItem(cancelOperationItem!)

        menu.addItem(NSMenuItem.separator())

        // === TRANSCRIPTS SECTION ===
        let transcriptsHeader = createHeaderItem("Transcripts")
        menu.addItem(transcriptsHeader)

        transcriptsMenu = NSMenu()
        copyLastTranscriptItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: #selector(copyLastTranscript),
            keyEquivalent: "c"
        )
        copyLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(copyLastTranscriptItem!)

        exportLastTranscriptItem = NSMenuItem(
            title: "Export Last Transcript...",
            action: #selector(exportLastTranscript),
            keyEquivalent: "e"
        )
        exportLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(exportLastTranscriptItem!)

        transcriptsMenu?.addItem(NSMenuItem.separator())

        recentTranscriptsSeparator = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentTranscriptsSeparator?.isEnabled = false
        transcriptsMenu?.addItem(recentTranscriptsSeparator!)

        let recentMenuItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentMenuItem.submenu = transcriptsMenu
        menu.addItem(recentMenuItem)

        menu.addItem(NSMenuItem.separator())

        // === OUTPUT SECTION ===
        let outputHeader = createHeaderItem("Output")
        menu.addItem(outputHeader)

        outputModeItem = NSMenuItem(
            title: "Mode: Clipboard",
            action: #selector(toggleOutputMode),
            keyEquivalent: "o"
        )
        outputModeItem?.target = self
        menu.addItem(outputModeItem!)

        aiEnhancementItem = NSMenuItem(
            title: "AI Enhancement: Off",
            action: #selector(toggleAIEnhancement),
            keyEquivalent: "a"
        )
        aiEnhancementItem?.target = self
        menu.addItem(aiEnhancementItem!)

        menu.addItem(NSMenuItem.separator())

        // === VIEW SECTION ===
        let viewHeader = createHeaderItem("View")
        menu.addItem(viewHeader)

        toggleFloatingIndicatorItem = NSMenuItem(
            title: "Floating Indicator: Off",
            action: #selector(toggleFloatingIndicator),
            keyEquivalent: "f"
        )
        toggleFloatingIndicatorItem?.target = self
        menu.addItem(toggleFloatingIndicatorItem!)

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login: Off",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: "l"
        )
        launchAtLoginItem?.target = self
        menu.addItem(launchAtLoginItem!)

        openHistoryItem = NSMenuItem(
            title: "Open History",
            action: #selector(openHistory),
            keyEquivalent: "h"
        )
        openHistoryItem?.target = self
        menu.addItem(openHistoryItem!)

        menu.addItem(NSMenuItem.separator())

        // === MODEL SECTION ===
        let modelHeader = createHeaderItem("Model")
        menu.addItem(modelHeader)

        modelMenu = NSMenu()
        currentModelItem = NSMenuItem(
            title: "Current: \(settingsStore.selectedModel.replacingOccurrences(of: "openai_whisper-", with: ""))",
            action: nil,
            keyEquivalent: ""
        )
        currentModelItem?.isEnabled = false
        modelMenu?.addItem(currentModelItem!)

        modelMenu?.addItem(NSMenuItem.separator())

        let modelMenuItem = NSMenuItem(title: "Switch Model", action: nil, keyEquivalent: "")
        modelMenuItem.submenu = modelMenu
        menu.addItem(modelMenuItem)

        menu.addItem(NSMenuItem.separator())

        // === APP SECTION ===
        let appHeader = createHeaderItem("App")
        menu.addItem(appHeader)

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
        updateDynamicItems()
    }

    private func createHeaderItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        )
        return item
    }

    private func updateRecentTranscriptsMenu() {
        guard let transcriptsMenu = transcriptsMenu else { return }

        // Remove old recent items (keep first 4: copy, export, separator, header)
        let itemsToRemove = transcriptsMenu.items.filter { item in
            guard let identifier = item.identifier?.rawValue else { return false }
            return identifier.starts(with: "recent_")
        }
        itemsToRemove.forEach { transcriptsMenu.removeItem($0) }

        // Add new recent items
        for (index, transcript) in recentTranscripts.enumerated() {
            let truncatedText = String(transcript.text.prefix(40))
            let displayText = truncatedText.isEmpty ? "(Empty)" : truncatedText
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            let item = NSMenuItem(
                title: "\(displayText)... (\(timeFormatter.string(from: transcript.timestamp)))",
                action: #selector(copyRecentTranscript(_:)),
                keyEquivalent: String(index + 1)
            )
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier("recent_\(transcript.id)")
            transcriptsMenu.addItem(item)
        }
    }

    func updateDynamicItems() {
        // Update output mode
        let outputModeText = settingsStore.outputMode == "clipboard" ? "Clipboard" : "Direct Insert"
        outputModeItem?.title = "Mode: \(outputModeText)"

        // Update AI enhancement
        let aiText = settingsStore.aiEnhancementEnabled ? "On" : "Off"
        aiEnhancementItem?.title = "AI Enhancement: \(aiText)"

        // Update floating indicator
        let indicatorText = settingsStore.floatingIndicatorEnabled ? "On" : "Off"
        toggleFloatingIndicatorItem?.title = "Floating Indicator: \(indicatorText)"

        // Update launch at login
        let launchAtLoginText = settingsStore.launchAtLogin ? "On" : "Off"
        launchAtLoginItem?.title = "Launch at Login: \(launchAtLoginText)"

        // Update model
        let modelShortName = settingsStore.selectedModel.replacingOccurrences(of: "openai_whisper-", with: "")
        currentModelItem?.title = "Current: \(modelShortName)"
    }

    func updateMenuState() {
        switch currentState {
        case .recording:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: "🔴 Recording",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            toggleRecordingItem?.title = "Stop Recording"
            toggleRecordingItem?.isEnabled = true
            clearAudioBufferItem?.isEnabled = true
            cancelOperationItem?.isEnabled = true
        case .processing:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: "⏳ Processing",
                attributes: [.foregroundColor: NSColor.systemBlue]
            )
            toggleRecordingItem?.title = "Processing..."
            toggleRecordingItem?.isEnabled = false
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = true
        case .idle:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: "● Ready",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
            toggleRecordingItem?.title = "Start Recording"
            toggleRecordingItem?.isEnabled = true
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task {
            await onToggleRecording?()
        }
    }

    @objc private func copyLastTranscript() {
        Task {
            await onCopyLastTranscript?()
        }
    }

    @objc private func exportLastTranscript() {
        Task {
            await onExportLastTranscript?()
        }
    }

    @objc private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let idString = sender.identifier?.rawValue,
              let id = UUID(uuidString: idString.replacingOccurrences(of: "recent_", with: "")),
              let transcript = recentTranscripts.first(where: { $0.id == id }) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([transcript.text as NSString])
    }

    @objc private func clearAudioBuffer() {
        Task {
            await onClearAudioBuffer?()
        }
    }

    @objc private func cancelOperation() {
        Task {
            await onCancelOperation?()
        }
    }

    @objc private func toggleOutputMode() {
        onToggleOutputMode?()
    }

    @objc private func toggleAIEnhancement() {
        onToggleAIControlled?()
    }

    @objc private func toggleFloatingIndicator() {
        onToggleFloatingIndicator?()
    }

    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin?()
    }

    @objc private func openHistory() {
        onOpenHistory?()
    }

    @objc private func openSettings() {
        openSettingsWindow(tab: .general)
    }

    private func openSettingsWindow(tab: SettingsTab) {
        if let existingWindow = settingsWindow {
            existingWindow.close()
            settingsWindow = nil
        }

        var settingsView = SettingsWindow(initialTab: tab)
        let rootView: AnyView
        if let container = modelContainer {
            rootView = AnyView(settingsView.modelContainer(container))
        } else {
            rootView = AnyView(settingsView)
        }
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Pindrop Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: AppTheme.Window.settingsDefaultWidth, height: AppTheme.Window.settingsDefaultHeight))
        window.minSize = NSSize(width: AppTheme.Window.settingsMinWidth, height: AppTheme.Window.settingsMinHeight)
        window.center()

        settingsWindow = window
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openMainWindow() {
        mainWindowController?.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private var cachedBaseIcon: NSImage?

    private func getBaseIcon() -> NSImage? {
        if let cached = cachedBaseIcon {
            return cached
        }

        guard let customIcon = NSImage(named: "PindropIcon") else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Pindrop")
        }

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

        cachedBaseIcon = resizedIcon
        return resizedIcon
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }

        button.layer?.sublayers?.filter { $0.name == "indicatorDot" }.forEach { $0.removeFromSuperlayer() }
        button.layer?.removeAllAnimations()

        button.image = getBaseIcon()
        button.image?.isTemplate = true
        button.contentTintColor = nil
        button.alphaValue = 1.0

        switch currentState {
        case .idle:
            break

        case .recording:
            addIndicatorDot(to: button, color: .systemRed, pulse: true)

        case .processing:
            addIndicatorDot(to: button, color: .systemYellow, pulse: true)
        }
    }

    private func addIndicatorDot(to button: NSStatusBarButton, color: NSColor, pulse: Bool) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let dotSize: CGFloat = 5
        let padding: CGFloat = 1

        let dotLayer = CALayer()
        dotLayer.name = "indicatorDot"
        dotLayer.backgroundColor = color.cgColor
        dotLayer.cornerRadius = dotSize / 2

        let buttonBounds = button.bounds
        dotLayer.frame = CGRect(
            x: buttonBounds.width - dotSize - padding,
            y: padding,
            width: dotSize,
            height: dotSize
        )

        layer.addSublayer(dotLayer)

        if pulse {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.3
            animation.duration = 0.6
            animation.autoreverses = true
            animation.repeatCount = .infinity
            dotLayer.add(animation, forKey: "pulse")
        }
    }

    func setRecordingState() {
        currentState = .recording
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
                .foregroundStyle(AppColors.accent)
                .frame(width: 16)

            Text(text)
                .font(.subheadline)
        }
    }
}
