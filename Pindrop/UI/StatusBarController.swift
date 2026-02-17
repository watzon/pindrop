import Foundation
import AppKit
import SwiftUI
import SwiftData
import os.log

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

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
    private var pasteLastTranscriptItem: NSMenuItem?
    private var exportLastTranscriptItem: NSMenuItem?
    private var recentTranscriptsSeparator: NSMenuItem?

    private var outputModeItem: NSMenuItem?
    private var aiEnhancementItem: NSMenuItem?
    private var promptPresetMenuItem: NSMenuItem?
    private var promptPresetMenu: NSMenu?
    private var reportIssueItem: NSMenuItem?
    private var inputDeviceMenuItem: NSMenuItem?
    private var inputDeviceMenu: NSMenu?

    private var toggleFloatingIndicatorItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var openHistoryItem: NSMenuItem?

    private var modelMenu: NSMenu?
    private var currentModelItem: NSMenuItem?
    private var checkForUpdatesItem: NSMenuItem?
    private var switchableModels: [(name: String, displayName: String)] = []

    private var aiModelMenu: NSMenu?
    private var currentAIModelItem: NSMenuItem?
    private let aiModelService = AIModelService()

    private var settingsWindow: NSWindow?
    private var welcomePopover: NSPopover?

    // MARK: - Callbacks

    var onToggleRecording: (() async -> Void)?
    var onShowApp: (() -> Void)?
    var onCopyLastTranscript: (() async -> Void)?
    var onPasteLastTranscript: (() async -> Void)?
    var onExportLastTranscript: (() async -> Void)?
    var onClearAudioBuffer: (() async -> Void)?
    var onCancelOperation: (() async -> Void)?
    var onToggleOutputMode: (() -> Void)?
    var onToggleAIControlled: (() -> Void)?
    var onSelectPromptPreset: ((String?) -> Void)?
    var onToggleFloatingIndicator: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onReportIssue: (() -> Void)?
    var onSelectInputDeviceUID: ((String) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onSelectAIModel: ((String) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onMenuWillOpen: (() async -> Void)?

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
        super.init()
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
        if let currentModel = switchableModels.first(where: { $0.name == modelName }) {
            currentModelItem?.title = "Current: \(currentModel.displayName)"
        } else {
            currentModelItem?.title = "Current: \(modelName.replacingOccurrences(of: "openai_whisper-", with: ""))"
        }
        refreshModelMenuItems()
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
        menu.delegate = self

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
        toggleRecordingItem?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(toggleRecordingItem!)

        clearAudioBufferItem = NSMenuItem(
            title: "Clear Audio Buffer",
            action: #selector(clearAudioBuffer),
            keyEquivalent: "x"
        )
        clearAudioBufferItem?.target = self
        clearAudioBufferItem?.isEnabled = false
        clearAudioBufferItem?.image = NSImage(systemSymbolName: "clear", accessibilityDescription: nil)
        menu.addItem(clearAudioBufferItem!)

        cancelOperationItem = NSMenuItem(
            title: "Cancel Operation",
            action: #selector(cancelOperation),
            keyEquivalent: ""
        )
        cancelOperationItem?.target = self
        cancelOperationItem?.isEnabled = false
        cancelOperationItem?.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
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

        pasteLastTranscriptItem = NSMenuItem(
            title: "Paste Last Transcript",
            action: #selector(pasteLastTranscript),
            keyEquivalent: ""
        )
        pasteLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(pasteLastTranscriptItem!)

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
        recentMenuItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
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
        outputModeItem?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(outputModeItem!)

        aiEnhancementItem = NSMenuItem(
            title: "AI Enhancement: Off",
            action: #selector(toggleAIEnhancement),
            keyEquivalent: "a"
        )
        aiEnhancementItem?.target = self
        aiEnhancementItem?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        menu.addItem(aiEnhancementItem!)

        promptPresetMenu = NSMenu()
        let customItem = NSMenuItem(
            title: "Custom",
            action: #selector(selectPromptPreset(_:)),
            keyEquivalent: ""
        )
        customItem.target = self
        customItem.identifier = NSUserInterfaceItemIdentifier("preset_custom")
        customItem.state = settingsStore.selectedPresetId == nil ? .on : .off
        promptPresetMenu?.addItem(customItem)

        promptPresetMenuItem = NSMenuItem(title: "Prompt Preset", action: nil, keyEquivalent: "")
        promptPresetMenuItem?.submenu = promptPresetMenu
        promptPresetMenuItem?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(promptPresetMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // === VIEW SECTION ===
        let viewHeader = createHeaderItem("View")
        menu.addItem(viewHeader)

        let showAppItem = NSMenuItem(
            title: "Show App",
            action: #selector(showApp),
            keyEquivalent: "0"
        )
        showAppItem.target = self
        showAppItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(showAppItem)

        openHistoryItem = NSMenuItem(
            title: "Open History",
            action: #selector(openHistory),
            keyEquivalent: "h"
        )
        openHistoryItem?.target = self
        openHistoryItem?.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(openHistoryItem!)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        inputDeviceMenu = NSMenu(title: "Change Microphone")
        inputDeviceMenuItem = NSMenuItem(title: "Change Microphone", action: nil, keyEquivalent: "")
        inputDeviceMenuItem?.submenu = inputDeviceMenu
        inputDeviceMenuItem?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        if let inputDeviceMenuItem {
            menu.addItem(inputDeviceMenuItem)
        }

        let languageMenu = NSMenu(title: "Select Language")
        let englishLanguageItem = NSMenuItem(title: "English (v1)", action: nil, keyEquivalent: "")
        englishLanguageItem.state = NSControl.StateValue.on
        englishLanguageItem.isEnabled = false
        languageMenu.addItem(englishLanguageItem)

        let languageMenuItem = NSMenuItem(title: "Select Language", action: nil, keyEquivalent: "")
        languageMenuItem.submenu = languageMenu
        languageMenuItem.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
        menu.addItem(languageMenuItem)

        menu.addItem(NSMenuItem.separator())

        toggleFloatingIndicatorItem = NSMenuItem(
            title: "Floating Indicator: Off",
            action: #selector(toggleFloatingIndicator),
            keyEquivalent: "f"
        )
        toggleFloatingIndicatorItem?.target = self
        toggleFloatingIndicatorItem?.image = NSImage(systemSymbolName: "pip", accessibilityDescription: nil)
        menu.addItem(toggleFloatingIndicatorItem!)

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login: Off",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: "l"
        )
        launchAtLoginItem?.target = self
        launchAtLoginItem?.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(launchAtLoginItem!)

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
        refreshModelMenuItems()

        let modelMenuItem = NSMenuItem(title: "Select Voice Model", action: nil, keyEquivalent: "")
        modelMenuItem.submenu = modelMenu
        modelMenuItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        menu.addItem(modelMenuItem)

        aiModelMenu = NSMenu()
        currentAIModelItem = NSMenuItem(
            title: "Current: \(settingsStore.aiModel)",
            action: nil,
            keyEquivalent: ""
        )
        currentAIModelItem?.isEnabled = false
        aiModelMenu?.addItem(currentAIModelItem!)

        aiModelMenu?.addItem(NSMenuItem.separator())
        refreshAIModelMenuItems()

        let aiModelMenuItem = NSMenuItem(title: "Select AI Model", action: nil, keyEquivalent: "")
        aiModelMenuItem.submenu = aiModelMenu
        aiModelMenuItem.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)
        menu.addItem(aiModelMenuItem)

        menu.addItem(NSMenuItem.separator())

        reportIssueItem = NSMenuItem(
            title: "Report an Issue",
            action: #selector(reportIssue),
            keyEquivalent: ""
        )
        reportIssueItem?.target = self
        reportIssueItem?.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        if let reportIssueItem {
            menu.addItem(reportIssueItem)
        }


        checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        )
        checkForUpdatesItem?.target = self
        checkForUpdatesItem?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(checkForUpdatesItem!)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Pindrop",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)

        updateMenuState()
        updateDynamicItems()
    }

    func updateSwitchableModels(_ models: [(name: String, displayName: String)]) {
        switchableModels = models.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        refreshModelMenuItems()
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

        // Update prompt preset checkmarks
        updatePromptPresetCheckmarks()

        // Update floating indicator
        let indicatorText = settingsStore.floatingIndicatorEnabled ? "On" : "Off"
        toggleFloatingIndicatorItem?.title = "Floating Indicator: \(indicatorText)"

        // Update launch at login
        let launchAtLoginText = settingsStore.launchAtLogin ? "On" : "Off"
        launchAtLoginItem?.title = "Launch at Login: \(launchAtLoginText)"

        // Update model
        if let currentModel = switchableModels.first(where: { $0.name == settingsStore.selectedModel }) {
            currentModelItem?.title = "Current: \(currentModel.displayName)"
        } else {
            let modelShortName = settingsStore.selectedModel.replacingOccurrences(of: "openai_whisper-", with: "")
            currentModelItem?.title = "Current: \(modelShortName)"
        }
        refreshModelMenuItems()


        refreshInputDeviceMenu()
        refreshAIModelMenuItems()
    }

    private func refreshModelMenuItems() {
        guard let modelMenu = modelMenu else { return }

        while modelMenu.items.count > 2 {
            modelMenu.removeItem(at: 2)
        }

        if switchableModels.isEmpty {
            let emptyItem = NSMenuItem(title: "No downloaded models", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            modelMenu.addItem(emptyItem)
            return
        }

        for model in switchableModels {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.name
            item.state = settingsStore.selectedModel == model.name ? NSControl.StateValue.on : NSControl.StateValue.off
            modelMenu.addItem(item)
        }
    }

    private func refreshAIModelMenuItems() {
        guard let aiModelMenu = aiModelMenu else { return }

        // Remove all items after the separator (index 1)
        while aiModelMenu.items.count > 2 {
            aiModelMenu.removeItem(at: 2)
        }

        let provider = settingsStore.currentAIProvider

        // Update current model display
        currentAIModelItem?.title = "Current: \(settingsStore.aiModel)"

        guard provider == .openai || provider == .openrouter else {
            let noModelsItem = NSMenuItem(title: "No models available", action: nil, keyEquivalent: "")
            noModelsItem.isEnabled = false
            aiModelMenu.addItem(noModelsItem)
            return
        }

        guard let cachedModels = aiModelService.getCachedModels(for: provider), !cachedModels.isEmpty else {
            let fetchItem = NSMenuItem(title: "Fetch models in Settings", action: nil, keyEquivalent: "")
            fetchItem.isEnabled = false
            aiModelMenu.addItem(fetchItem)
            return
        }

        for model in cachedModels {
            let item = NSMenuItem(
                title: model.name,
                action: #selector(selectAIModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model.id
            item.state = settingsStore.aiModel == model.id ? NSControl.StateValue.on : NSControl.StateValue.off
            aiModelMenu.addItem(item)
        }
    }

    private func refreshInputDeviceMenu() {
        guard let inputDeviceMenu = inputDeviceMenu else { return }

        inputDeviceMenu.removeAllItems()

        let selectedUID = settingsStore.selectedInputDeviceUID
        let availableDevices = AudioDeviceManager.inputDevices()

        let systemDefaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectInputDevice(_:)),
            keyEquivalent: ""
        )
        systemDefaultItem.target = self
        systemDefaultItem.representedObject = ""
        systemDefaultItem.state = selectedUID.isEmpty ? NSControl.StateValue.on : NSControl.StateValue.off
        inputDeviceMenu.addItem(systemDefaultItem)

        if !availableDevices.isEmpty {
            inputDeviceMenu.addItem(.separator())
        }

        for device in availableDevices {
            let item = NSMenuItem(
                title: device.displayName,
                action: #selector(selectInputDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            item.state = selectedUID == device.uid ? NSControl.StateValue.on : NSControl.StateValue.off
            inputDeviceMenu.addItem(item)
        }

        if !selectedUID.isEmpty && !availableDevices.contains(where: { $0.uid == selectedUID }) {
            inputDeviceMenu.addItem(.separator())

            let unavailableItem = NSMenuItem(title: "Unavailable device", action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            unavailableItem.state = NSControl.StateValue.on
            inputDeviceMenu.addItem(unavailableItem)
        }
    }

    func updatePromptPresets(_ presets: [(id: String, name: String)]) {
        guard let promptPresetMenu = promptPresetMenu else { return }

        promptPresetMenu.removeAllItems()

        // "Custom" item (no preset selected)
        let customItem = NSMenuItem(
            title: "Custom",
            action: #selector(selectPromptPreset(_:)),
            keyEquivalent: ""
        )
        customItem.target = self
        customItem.identifier = NSUserInterfaceItemIdentifier("preset_custom")
        customItem.state = settingsStore.selectedPresetId == nil ? .on : .off
        promptPresetMenu.addItem(customItem)

        if !presets.isEmpty {
            promptPresetMenu.addItem(NSMenuItem.separator())
        }

        for preset in presets {
            let item = NSMenuItem(
                title: preset.name,
                action: #selector(selectPromptPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier("preset_\(preset.id)")
            item.state = settingsStore.selectedPresetId == preset.id ? .on : .off
            promptPresetMenu.addItem(item)
        }
    }

    private func updatePromptPresetCheckmarks() {
        guard let promptPresetMenu = promptPresetMenu else { return }

        for item in promptPresetMenu.items {
            guard let identifier = item.identifier?.rawValue else { continue }
            if identifier == "preset_custom" {
                item.state = settingsStore.selectedPresetId == nil ? .on : .off
            } else {
                let presetId = identifier.replacingOccurrences(of: "preset_", with: "")
                item.state = settingsStore.selectedPresetId == presetId ? .on : .off
            }
        }
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
            checkForUpdatesItem?.isEnabled = false
        case .processing:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: "⏳ Processing",
                attributes: [.foregroundColor: NSColor.systemBlue]
            )
            toggleRecordingItem?.title = "Processing..."
            toggleRecordingItem?.isEnabled = false
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = true
            checkForUpdatesItem?.isEnabled = false
        case .idle:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: "● Ready",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
            toggleRecordingItem?.title = "Start Recording"
            toggleRecordingItem?.isEnabled = true
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = false
            checkForUpdatesItem?.isEnabled = true
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

    @objc private func pasteLastTranscript() {
        Task {
            await onPasteLastTranscript?()
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

    @objc private func selectPromptPreset(_ sender: NSMenuItem) {
        guard let identifier = sender.identifier?.rawValue else { return }
        let presetId: String? = identifier == "preset_custom" ? nil : identifier.replacingOccurrences(of: "preset_", with: "")
        onSelectPromptPreset?(presetId)
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


    @objc private func reportIssue() {
        onReportIssue?()
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        onSelectInputDeviceUID?(uid)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelName = sender.representedObject as? String else { return }
        onSelectModel?(modelName)
    }

    @objc private func selectAIModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        settingsStore.aiModel = modelId
        onSelectAIModel?(modelId)
        refreshAIModelMenuItems()
    }

    @objc private func showApp() {
        onShowApp?()
    }

    @objc private func openSettings() {
        openSettingsWindow(tab: .general)
    }

    private func openSettingsWindow(tab: SettingsTab) {
        if let existingWindow = settingsWindow {
            existingWindow.close()
            settingsWindow = nil
        }

        let settingsView = SettingsWindow(settings: settingsStore, initialTab: tab)
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }

        Task { @MainActor in
            await onMenuWillOpen?()
            updateDynamicItems()
        }
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
