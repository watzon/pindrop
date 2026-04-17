import Foundation
import AppKit
import SwiftUI
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
    private var languageMenuItem: NSMenuItem?
    private var languageMenu: NSMenu?

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
    var onSelectLanguage: ((AppLanguage) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onSelectAIModel: ((String) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onMenuWillOpen: (() async -> Void)?

    // Recent transcripts for submenu
    private(set) var recentTranscripts: [(id: UUID, text: String, timestamp: Date)] = []

    // MARK: - StateNo idea

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

    func setMainWindowController(_ controller: MainWindowController) {
        self.mainWindowController = controller
    }

    func showSettings(tab: SettingsTab = .general) {
        guard let mainWindowController else {
            Log.ui.error("MainWindowController not set - cannot show settings")
            return
        }

        mainWindowController.showSettings(tab: tab)
    }

    func reloadLocalizedStrings() {
        setupMenu()
        updateRecentTranscriptsMenu()
        updateDynamicItems()
    }

    func updateRecentTranscripts(_ transcripts: [(id: UUID, text: String, timestamp: Date)]) {
        self.recentTranscripts = Array(transcripts.prefix(5))
        updateRecentTranscriptsMenu()
    }

    func updateSelectedModel(_ modelName: String) {
        if let currentModel = switchableModels.first(where: { $0.name == modelName }) {
            currentModelItem?.title = String(format: localized("Current: %@", locale: locale), currentModel.displayName)
        } else {
            currentModelItem?.title = String(
                format: localized("Current: %@", locale: locale),
                modelName.replacingOccurrences(of: "openai_whisper-", with: "")
            )
        }
        refreshModelMenuItems()
    }

    private var locale: Locale {
        settingsStore.selectedAppLanguage.locale
    }

    // MARK: - Setup

    private func setupStatusItem() {
        if let existingStatusItem = statusItem {
            NSStatusBar.system.removeStatusItem(existingStatusItem)
        }

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = newStatusItem

        guard let button = newStatusItem.button else {
            Log.ui.error("Failed to create status bar button; retrying on next run loop")
            DispatchQueue.main.async { [weak self] in
                self?.ensureStatusItem()
            }
            return
        }

        configureStatusButton(button)
        newStatusItem.menu = menu
    }

    func ensureStatusItem() {
        guard let statusItem else {
            setupStatusItem()
            return
        }

        guard let button = statusItem.button else {
            Log.ui.error("Status item exists without a button; recreating")
            setupStatusItem()
            return
        }

        configureStatusButton(button)
        statusItem.menu = menu
        updateStatusBarIcon()
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        button.imagePosition = .imageOnly
        button.appearsDisabled = false

        button.image = getBaseIcon()
        button.image?.isTemplate = true

        button.toolTip = "Pindrop"
    }

    private func setupMenu() {
        menu.removeAllItems()
        menu.delegate = self

        // === RECORDING SECTION ===
        let recordingHeader = createHeaderItem(localized("Recording", locale: locale))
        menu.addItem(recordingHeader)

        recordingStatusItem = NSMenuItem(title: localized("● Ready", locale: locale), action: nil, keyEquivalent: "")
        recordingStatusItem?.isEnabled = false
        recordingStatusItem?.attributedTitle = NSAttributedString(
            string: localized("● Ready", locale: locale),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(recordingStatusItem!)

        toggleRecordingItem = NSMenuItem(
            title: localized("Start Recording", locale: locale),
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        toggleRecordingItem?.target = self
        toggleRecordingItem?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        menu.addItem(toggleRecordingItem!)

        clearAudioBufferItem = NSMenuItem(
            title: localized("Clear Audio Buffer", locale: locale),
            action: #selector(clearAudioBuffer),
            keyEquivalent: "x"
        )
        clearAudioBufferItem?.target = self
        clearAudioBufferItem?.isEnabled = false
        clearAudioBufferItem?.image = NSImage(systemSymbolName: "clear", accessibilityDescription: nil)
        menu.addItem(clearAudioBufferItem!)

        cancelOperationItem = NSMenuItem(
            title: localized("Cancel Operation", locale: locale),
            action: #selector(cancelOperation),
            keyEquivalent: ""
        )
        cancelOperationItem?.target = self
        cancelOperationItem?.isEnabled = false
        cancelOperationItem?.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
        menu.addItem(cancelOperationItem!)

        menu.addItem(NSMenuItem.separator())

        // === TRANSCRIPTS SECTION ===
        let transcriptsHeader = createHeaderItem(localized("Transcripts", locale: locale))
        menu.addItem(transcriptsHeader)

        transcriptsMenu = NSMenu()
        copyLastTranscriptItem = NSMenuItem(
            title: localized("Copy Last Transcript", locale: locale),
            action: #selector(copyLastTranscript),
            keyEquivalent: "c"
        )
        copyLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(copyLastTranscriptItem!)

        pasteLastTranscriptItem = NSMenuItem(
            title: localized("Paste Last Transcript", locale: locale),
            action: #selector(pasteLastTranscript),
            keyEquivalent: ""
        )
        pasteLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(pasteLastTranscriptItem!)

        exportLastTranscriptItem = NSMenuItem(
            title: localized("Export Last Transcript...", locale: locale),
            action: #selector(exportLastTranscript),
            keyEquivalent: "e"
        )
        exportLastTranscriptItem?.target = self
        transcriptsMenu?.addItem(exportLastTranscriptItem!)

        transcriptsMenu?.addItem(NSMenuItem.separator())

        recentTranscriptsSeparator = NSMenuItem(title: localized("Recent", locale: locale), action: nil, keyEquivalent: "")
        recentTranscriptsSeparator?.isEnabled = false
        transcriptsMenu?.addItem(recentTranscriptsSeparator!)

        let recentMenuItem = NSMenuItem(title: localized("Recent Transcripts", locale: locale), action: nil, keyEquivalent: "")
        recentMenuItem.submenu = transcriptsMenu
        recentMenuItem.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(recentMenuItem)

        menu.addItem(NSMenuItem.separator())

        // === OUTPUT SECTION ===
        let outputHeader = createHeaderItem(localized("Output", locale: locale))
        menu.addItem(outputHeader)

        outputModeItem = NSMenuItem(
            title: String(format: localized("Mode: %@", locale: locale), localized("Clipboard", locale: locale)),
            action: #selector(toggleOutputMode),
            keyEquivalent: "o"
        )
        outputModeItem?.target = self
        outputModeItem?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(outputModeItem!)

        aiEnhancementItem = NSMenuItem(
            title: String(format: localized("AI Enhancement: %@", locale: locale), localized("Off", locale: locale)),
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

        promptPresetMenuItem = NSMenuItem(title: localized("Prompt Preset", locale: locale), action: nil, keyEquivalent: "")
        promptPresetMenuItem?.submenu = promptPresetMenu
        promptPresetMenuItem?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        menu.addItem(promptPresetMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // === VIEW SECTION ===
        let viewHeader = createHeaderItem(localized("View", locale: locale))
        menu.addItem(viewHeader)

        let showAppItem = NSMenuItem(
            title: localized("Show App", locale: locale),
            action: #selector(showApp),
            keyEquivalent: "0"
        )
        showAppItem.target = self
        showAppItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(showAppItem)

        openHistoryItem = NSMenuItem(
            title: localized("Open History", locale: locale),
            action: #selector(openHistory),
            keyEquivalent: "h"
        )
        openHistoryItem?.target = self
        openHistoryItem?.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(openHistoryItem!)

        let settingsItem = NSMenuItem(
            title: localized("Settings...", locale: locale),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        inputDeviceMenu = NSMenu(title: localized("Change Microphone", locale: locale))
        inputDeviceMenuItem = NSMenuItem(title: localized("Change Microphone", locale: locale), action: nil, keyEquivalent: "")
        inputDeviceMenuItem?.submenu = inputDeviceMenu
        inputDeviceMenuItem?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        if let inputDeviceMenuItem {
            menu.addItem(inputDeviceMenuItem)
        }

        languageMenu = NSMenu(title: localized("Select Language", locale: locale))
        languageMenuItem = NSMenuItem(title: localized("Select Language", locale: locale), action: nil, keyEquivalent: "")
        languageMenuItem?.submenu = languageMenu
        languageMenuItem?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
        if let languageMenuItem {
            menu.addItem(languageMenuItem)
        }
        refreshLanguageMenuItems()

        menu.addItem(NSMenuItem.separator())

        toggleFloatingIndicatorItem = NSMenuItem(
            title: String(format: localized("Floating Indicator: %@", locale: locale), localized("Off", locale: locale)),
            action: #selector(toggleFloatingIndicator),
            keyEquivalent: "f"
        )
        toggleFloatingIndicatorItem?.target = self
        toggleFloatingIndicatorItem?.image = NSImage(systemSymbolName: "pip", accessibilityDescription: nil)
        menu.addItem(toggleFloatingIndicatorItem!)

        launchAtLoginItem = NSMenuItem(
            title: String(format: localized("Launch at Login: %@", locale: locale), localized("Off", locale: locale)),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: "l"
        )
        launchAtLoginItem?.target = self
        launchAtLoginItem?.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(launchAtLoginItem!)

        menu.addItem(NSMenuItem.separator())

        // === MODEL SECTION ===
        let modelHeader = createHeaderItem(localized("Model", locale: locale))
        menu.addItem(modelHeader)

        modelMenu = NSMenu()
        currentModelItem = NSMenuItem(
            title: String(format: localized("Current: %@", locale: locale), settingsStore.selectedModel.replacingOccurrences(of: "openai_whisper-", with: "")),
            action: nil,
            keyEquivalent: ""
        )
        currentModelItem?.isEnabled = false
        modelMenu?.addItem(currentModelItem!)

        modelMenu?.addItem(NSMenuItem.separator())
        refreshModelMenuItems()

        let modelMenuItem = NSMenuItem(title: localized("Select Voice Model", locale: locale), action: nil, keyEquivalent: "")
        modelMenuItem.submenu = modelMenu
        modelMenuItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        menu.addItem(modelMenuItem)

        aiModelMenu = NSMenu()
        currentAIModelItem = NSMenuItem(
            title: String(format: localized("Current: %@", locale: locale), settingsStore.assignment(for: .transcriptionEnhancement)?.modelID ?? ""),
            action: nil,
            keyEquivalent: ""
        )
        currentAIModelItem?.isEnabled = false
        aiModelMenu?.addItem(currentAIModelItem!)

        aiModelMenu?.addItem(NSMenuItem.separator())
        refreshAIModelMenuItems()

        let aiModelMenuItem = NSMenuItem(title: localized("Select AI Model", locale: locale), action: nil, keyEquivalent: "")
        aiModelMenuItem.submenu = aiModelMenu
        aiModelMenuItem.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)
        menu.addItem(aiModelMenuItem)

        menu.addItem(NSMenuItem.separator())

        reportIssueItem = NSMenuItem(
            title: localized("Report an Issue", locale: locale),
            action: #selector(reportIssue),
            keyEquivalent: ""
        )
        reportIssueItem?.target = self
        reportIssueItem?.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        if let reportIssueItem {
            menu.addItem(reportIssueItem)
        }


        checkForUpdatesItem = NSMenuItem(
            title: localized("Check for Updates...", locale: locale),
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        )
        checkForUpdatesItem?.target = self
        checkForUpdatesItem?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(checkForUpdatesItem!)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: localized("Quit Pindrop", locale: locale),
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
            let displayText = truncatedText.isEmpty ? localized("(Empty)", locale: locale) : truncatedText
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
        let outputModeText = settingsStore.outputMode == "clipboard"
            ? localized("Clipboard", locale: locale)
            : localized("Direct Insert", locale: locale)
        outputModeItem?.title = String(format: localized("Mode: %@", locale: locale), outputModeText)

        // Update AI enhancement
        let aiText = settingsStore.assignment(for: .transcriptionEnhancement) != nil ? localized("On", locale: locale) : localized("Off", locale: locale)
        aiEnhancementItem?.title = String(format: localized("AI Enhancement: %@", locale: locale), aiText)

        // Update prompt preset checkmarks
        updatePromptPresetCheckmarks()

        // Update floating indicator
        let indicatorText = settingsStore.floatingIndicatorEnabled ? localized("On", locale: locale) : localized("Off", locale: locale)
        toggleFloatingIndicatorItem?.title = String(format: localized("Floating Indicator: %@", locale: locale), indicatorText)

        // Update launch at login
        let launchAtLoginText = settingsStore.launchAtLogin ? localized("On", locale: locale) : localized("Off", locale: locale)
        launchAtLoginItem?.title = String(format: localized("Launch at Login: %@", locale: locale), launchAtLoginText)

        // Update model
        if let currentModel = switchableModels.first(where: { $0.name == settingsStore.selectedModel }) {
            currentModelItem?.title = String(format: localized("Current: %@", locale: locale), currentModel.displayName)
        } else {
            let modelShortName = settingsStore.selectedModel.replacingOccurrences(of: "openai_whisper-", with: "")
            currentModelItem?.title = String(format: localized("Current: %@", locale: locale), modelShortName)
        }
        refreshModelMenuItems()


        refreshInputDeviceMenu()
        refreshLanguageMenuItems()
        refreshAIModelMenuItems()
    }

    private func refreshModelMenuItems() {
        guard let modelMenu = modelMenu else { return }

        while modelMenu.items.count > 2 {
            modelMenu.removeItem(at: 2)
        }

        if switchableModels.isEmpty {
            let emptyItem = NSMenuItem(title: localized("No downloaded models", locale: locale), action: nil, keyEquivalent: "")
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

        let assignment = settingsStore.assignment(for: .transcriptionEnhancement)
        let currentModelID = assignment?.modelID ?? ""
        let provider: AIProvider = assignment
            .flatMap { settingsStore.provider(withID: $0.providerID)?.kind }
            ?? .openai

        // Update current model display
        currentAIModelItem?.title = String(format: localized("Current: %@", locale: locale), currentModelID)

        guard provider == .openai || provider == .openrouter else {
            let noModelsItem = NSMenuItem(title: localized("No models available", locale: locale), action: nil, keyEquivalent: "")
            noModelsItem.isEnabled = false
            aiModelMenu.addItem(noModelsItem)
            return
        }

        guard let cachedModels = aiModelService.getCachedModels(for: provider), !cachedModels.isEmpty else {
            let fetchItem = NSMenuItem(title: localized("Fetch models in Models", locale: locale), action: nil, keyEquivalent: "")
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
            item.state = currentModelID == model.id ? NSControl.StateValue.on : NSControl.StateValue.off
            aiModelMenu.addItem(item)
        }
    }

    private func refreshInputDeviceMenu() {
        guard let inputDeviceMenu = inputDeviceMenu else { return }

        inputDeviceMenu.removeAllItems()

        let selectedUID = settingsStore.selectedInputDeviceUID
        let availableDevices = AudioDeviceManager.inputDevices()

        let systemDefaultItem = NSMenuItem(
            title: localized("System Default", locale: locale),
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

            let unavailableItem = NSMenuItem(title: localized("Unavailable device", locale: locale), action: nil, keyEquivalent: "")
            unavailableItem.isEnabled = false
            unavailableItem.state = NSControl.StateValue.on
            inputDeviceMenu.addItem(unavailableItem)
        }
    }

    private func refreshLanguageMenuItems() {
        guard let languageMenu = languageMenu else { return }

        languageMenu.removeAllItems()

        let selectedLanguage = settingsStore.selectedAppLanguage
        let tier1Languages = AppLanguage.allCases.filter(\.isSelectable)
        let tier2Languages = AppLanguage.allCases.filter { !$0.isSelectable }

        for language in tier1Languages {
            let item = NSMenuItem(
                title: language.displayName(locale: locale),
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = selectedLanguage == language ? .on : .off
            languageMenu.addItem(item)
        }

        if !tier2Languages.isEmpty {
            languageMenu.addItem(.separator())

            let upcomingItem = NSMenuItem(title: localized("Coming Soon", locale: locale), action: nil, keyEquivalent: "")
            upcomingItem.isEnabled = false
            languageMenu.addItem(upcomingItem)

            for language in tier2Languages {
                let item = NSMenuItem(title: language.pickerLabel(locale: locale), action: nil, keyEquivalent: "")
                item.isEnabled = false
                languageMenu.addItem(item)
            }
        }
    }

    func updatePromptPresets(_ presets: [(id: String, name: String)]) {
        guard let promptPresetMenu = promptPresetMenu else { return }

        promptPresetMenu.removeAllItems()

        // "Custom" item (no preset selected)
        let customItem = NSMenuItem(
            title: localized("Custom", locale: locale),
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
                string: localized("🔴 Recording", locale: locale),
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            toggleRecordingItem?.title = localized("Stop Recording", locale: locale)
            toggleRecordingItem?.isEnabled = true
            clearAudioBufferItem?.isEnabled = true
            cancelOperationItem?.isEnabled = true
            checkForUpdatesItem?.isEnabled = false
        case .processing:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: localized("⏳ Processing", locale: locale),
                attributes: [.foregroundColor: NSColor.systemBlue]
            )
            toggleRecordingItem?.title = localized("Processing...", locale: locale)
            toggleRecordingItem?.isEnabled = false
            clearAudioBufferItem?.isEnabled = false
            cancelOperationItem?.isEnabled = true
            checkForUpdatesItem?.isEnabled = false
        case .idle:
            recordingStatusItem?.attributedTitle = NSAttributedString(
                string: localized("● Ready", locale: locale),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
            toggleRecordingItem?.title = localized("Start Recording", locale: locale)
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

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        settingsStore.selectedAppLanguage = language
        onSelectLanguage?(language)
        refreshLanguageMenuItems()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let modelName = sender.representedObject as? String else { return }
        onSelectModel?(modelName)
    }

    @objc private func selectAIModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        if let existing = settingsStore.assignment(for: .transcriptionEnhancement) {
            var updated = existing
            updated.modelID = modelId
            settingsStore.setAssignment(updated, for: .transcriptionEnhancement)
        }
        onSelectAIModel?(modelId)
        refreshAIModelMenuItems()
    }

    @objc private func showApp() {
        onShowApp?()
    }

    @objc private func openSettings() {
        showSettings(tab: .general)
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

        let targetSize: CGFloat = 18

        let resizedIcon = NSImage(size: NSSize(width: targetSize, height: targetSize))
        resizedIcon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        customIcon.draw(
            in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize),
            from: NSRect(origin: .zero, size: customIcon.size),
            operation: .copy,
            fraction: 1.0
        )
        resizedIcon.unlockFocus()
        resizedIcon.isTemplate = true

        cachedBaseIcon = resizedIcon
        return resizedIcon
    }

    /// Returns a small center-dot-only image for use during recording/processing
    /// when the static rings are replaced by animated expanding ones.
    private var cachedDotIcon: NSImage?

    private func getDotIcon() -> NSImage? {
        if let cached = cachedDotIcon { return cached }

        let size: CGFloat = 18
        let dotRadius: CGFloat = 2.0

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(
            x: (size - dotRadius * 2) / 2,
            y: (size - dotRadius * 2) / 2,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
        NSColor.black.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true

        cachedDotIcon = image
        return image
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }

        removeRippleAnimation(from: button)

        button.contentTintColor = nil
        button.alphaValue = 1.0

        switch currentState {
        case .idle:
            button.image = getBaseIcon()
            button.image?.isTemplate = true

        case .recording:
            button.image = getDotIcon()
            button.image?.isTemplate = true
            addRippleAnimation(to: button, color: NSColor.systemOrange)

        case .processing:
            button.image = getDotIcon()
            button.image?.isTemplate = true
            addRippleAnimation(to: button, color: NSColor.systemYellow)
        }
    }

    // MARK: - Ripple Animation

    private func addRippleAnimation(to button: NSStatusBarButton, color: NSColor) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let bounds = button.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxRadius: CGFloat = bounds.width * 0.48

        // Two expanding rings offset by half cycle, matching the animated SVG
        for i in 0..<2 {
            let ring = CAShapeLayer()
            ring.name = "rippleRing"
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = 1.5
            ring.opacity = 0

            let startPath = CGPath(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2), transform: nil)
            let endPath = CGPath(ellipseIn: CGRect(x: center.x - maxRadius, y: center.y - maxRadius, width: maxRadius * 2, height: maxRadius * 2), transform: nil)

            ring.path = endPath
            layer.addSublayer(ring)

            let duration: CFTimeInterval = 2.0
            let beginTime = CACurrentMediaTime() + Double(i) * (duration / 2.0)

            let pathAnim = CABasicAnimation(keyPath: "path")
            pathAnim.fromValue = startPath
            pathAnim.toValue = endPath

            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnim.values = [0.0, 0.7, 0.0]
            opacityAnim.keyTimes = [0.0, 0.15, 1.0]

            let widthAnim = CABasicAnimation(keyPath: "lineWidth")
            widthAnim.fromValue = 2.0
            widthAnim.toValue = 0.3

            let group = CAAnimationGroup()
            group.animations = [pathAnim, opacityAnim, widthAnim]
            group.duration = duration
            group.beginTime = beginTime
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0, 0.35, 1)

            ring.add(group, forKey: "ripple")
        }
    }

    private func removeRippleAnimation(from button: NSStatusBarButton) {
        button.layer?.sublayers?
            .filter { $0.name == "rippleRing" }
            .forEach { $0.removeFromSuperlayer() }
        button.layer?.removeAllAnimations()
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
            }
            .environment(\.locale, locale))
            popover.behavior = .transient
            popover.animates = true
            welcomePopover = popover
        }

        welcomePopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

struct WelcomePopoverView: View {
    @Environment(\.locale) private var locale
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconView(icon: .hand, size: 24)
                    .foregroundStyle(.yellow)

                Text(localized("You're all set!", locale: locale))
                    .font(.headline)
            }

            Text(localized("Click this icon anytime to:", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                popoverItem(icon: .record, text: localized("Start/stop recording", locale: locale))
                popoverItem(icon: .settings, text: localized("Open settings", locale: locale))
                popoverItem(icon: .clock, text: localized("View transcription history", locale: locale))
            }

            Divider()

            HStack {
                Text(localized("Or just use your hotkey!", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(localized("Got it", locale: locale)) {
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
