//
//  AppCoordinator.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import AppKit
import os.log

extension Notification.Name {
    static let switchModel = Notification.Name("com.pindrop.switchModel")
    static let modelActiveChanged = Notification.Name("com.pindrop.modelActiveChanged")
    static let requestActiveModel = Notification.Name("com.pindrop.requestActiveModel")
}

struct HotkeyConflict: Equatable {
    let existingIdentifier: String
    let incomingIdentifier: String
    let combination: HotkeyRegistrationState.Combination

    var conflictKey: String {
        [existingIdentifier, incomingIdentifier]
            .sorted()
            .joined(separator: "|") + "|\(combination.keyCode)|\(combination.modifiers)"
    }
}

struct HotkeyRegistrationState {
    struct Combination: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private(set) var registeredIdentifiersByCombination: [Combination: String] = [:]

    static func shouldRegisterHotkeys(hasCompletedOnboarding: Bool) -> Bool {
        hasCompletedOnboarding
    }

    mutating func register(
        identifier: String,
        keyCode: UInt32,
        modifiers: UInt32
    ) -> HotkeyConflict? {
        let combination = Combination(keyCode: keyCode, modifiers: modifiers)

        if let existingIdentifier = registeredIdentifiersByCombination[combination] {
            return HotkeyConflict(
                existingIdentifier: existingIdentifier,
                incomingIdentifier: identifier,
                combination: combination
            )
        }

        registeredIdentifiersByCombination[combination] = identifier
        return nil
    }
}

@MainActor
@Observable
final class AppCoordinator {

    private enum RecordingTriggerSource: String {
        case statusBarMenu = "status-bar-menu"
        case hotkeyToggle = "hotkey-toggle"
        case hotkeyPushToTalk = "hotkey-push-to-talk"
        case hotkeyQuickCapturePTT = "hotkey-quick-capture-ptt"
        case hotkeyQuickCaptureToggle = "hotkey-quick-capture-toggle"
        case floatingIndicatorStop = "floating-indicator-stop"
        case pillIndicatorStop = "pill-indicator-stop"
        case pillIndicatorStart = "pill-indicator-start"
    }

    // MARK: - Services
    
    let permissionManager: PermissionManager
    let audioRecorder: AudioRecorder
    let transcriptionService: TranscriptionService
    let modelManager: ModelManager
    let aiEnhancementService: AIEnhancementService
    let hotkeyManager: HotkeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    let updateService: UpdateService
    let outputManager: OutputManager
    let historyStore: HistoryStore
    let dictionaryStore: DictionaryStore
    let settingsStore: SettingsStore
    let notesStore: NotesStore
    let contextCaptureService: ContextCaptureService
    let contextEngineService: ContextEngineService
    let promptPresetStore: PromptPresetStore
    let mentionRewriteService: MentionRewriteService

    // MARK: - UI Controllers
    
    let statusBarController: StatusBarController
    let floatingIndicatorController: FloatingIndicatorController
    let pillFloatingIndicatorController: PillFloatingIndicatorController
    let onboardingController: OnboardingWindowController
    let splashController: SplashWindowController
    let mainWindowController: MainWindowController
    let noteEditorWindowController: NoteEditorWindowController
    
    // MARK: - Quick Capture State
    
    private var isQuickCaptureMode = false
    private var quickCaptureTranscription: String?
    
    // MARK: - State
    
    private(set) var activeModelName: String?
    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var error: Error?
    
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var capturedContext: CapturedContext?
    private var capturedSnapshot: ContextSnapshot?
    private var capturedAdapterCapabilities: AppAdapterCapabilities?
    private var capturedRoutingSignal: PromptRoutingSignal?
    private var recordingStartAttemptCounter: UInt64 = 0
    private var reportedHotkeyConflicts = Set<String>()
    private let appContextAdapterRegistry = AppContextAdapterRegistry()
    private let promptRoutingResolver: any PromptRoutingResolver = NoOpPromptRoutingResolver()
    private var lastObservedOutputMode: String = ""
    private var hasRequestedAccessibilityPermissionThisLaunch = false
    private var hasShownAccessibilityFallbackAlertThisLaunch = false

    // MARK: - Dictionary Replacements
    
    /// Stores the last applied dictionary replacements for use in AI enhancement prompts
    var lastAppliedReplacements: [(original: String, replacement: String)] = []
    
    // MARK: - Escape Key Cancellation
    
    private var escapeEventTap: CFMachPort?
    private var escapeRunLoopSource: CFRunLoopSource?
    private var escapeGlobalMonitor: Any?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private var modifierGlobalMonitor: Any?
    private var lastEscapeTime: Date?
    private var lastEscapeSignalTime: Date?
    private let doubleEscapeThreshold: TimeInterval = 0.4
    private let duplicateEscapeSignalThreshold: TimeInterval = 0.08
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.permissionManager = PermissionManager()
        do {
            self.audioRecorder = try AudioRecorder(permissionManager: permissionManager)
        } catch {
            Log.app.error("Failed to initialize AudioRecorder: \(error)")
            fatalError("Failed to initialize AudioRecorder: \(error)")
        }
        self.transcriptionService = TranscriptionService()
        self.modelManager = ModelManager()
        self.aiEnhancementService = AIEnhancementService()
        self.hotkeyManager = HotkeyManager()
        self.launchAtLoginManager = LaunchAtLoginManager()
        self.updateService = UpdateService()
        self.settingsStore = SettingsStore()
        self.lastObservedOutputMode = self.settingsStore.outputMode
        self.audioRecorder.setPreferredInputDeviceUID(settingsStore.selectedInputDeviceUID)
        
        let initialOutputMode: OutputMode = settingsStore.outputMode == "directInsert" ? .directInsert : .clipboard
        self.outputManager = OutputManager(outputMode: initialOutputMode)
        self.historyStore = HistoryStore(modelContext: modelContext)
        self.dictionaryStore = DictionaryStore(modelContext: modelContext)
        self.notesStore = NotesStore(modelContext: modelContext, aiEnhancementService: aiEnhancementService, settingsStore: settingsStore)
        self.contextCaptureService = ContextCaptureService()
        self.contextEngineService = ContextEngineService()
        self.promptPresetStore = PromptPresetStore(modelContext: modelContext)
        self.mentionRewriteService = MentionRewriteService()

        self.statusBarController = StatusBarController(
            audioRecorder: audioRecorder,
            settingsStore: settingsStore
        )
        self.statusBarController.setModelContainer(modelContainer)
        self.floatingIndicatorController = FloatingIndicatorController()
        self.pillFloatingIndicatorController = PillFloatingIndicatorController()
        self.onboardingController = OnboardingWindowController()
        let splashState = SplashScreenState()
        self.splashController = SplashWindowController(state: splashState)
        self.mainWindowController = MainWindowController()
        self.mainWindowController.setModelContainer(modelContainer)
        self.noteEditorWindowController = NoteEditorWindowController()
        self.noteEditorWindowController.setModelContainer(modelContainer)
        self.mainWindowController.onOpenSettings = { [weak self] in
            self?.statusBarController.showSettings(tab: .general)
        }

        self.statusBarController.onToggleRecording = { [weak self] in
            await self?.handleToggleRecording(source: .statusBarMenu)
        }

        self.statusBarController.onCopyLastTranscript = { [weak self] in
            await self?.handleCopyLastTranscript()
        }

        self.statusBarController.onExportLastTranscript = { [weak self] in
            await self?.handleExportLastTranscript()
        }

        self.statusBarController.onClearAudioBuffer = { [weak self] in
            await self?.handleClearAudioBuffer()
        }

        self.statusBarController.onCancelOperation = { [weak self] in
            await self?.handleCancelOperation()
        }

        self.statusBarController.onToggleOutputMode = { [weak self] in
            self?.handleToggleOutputMode()
        }

        self.statusBarController.onToggleAIControlled = { [weak self] in
            self?.handleToggleAIEnhancement()
        }

        self.statusBarController.onSelectPromptPreset = { [weak self] presetId in
            self?.handleSelectPromptPreset(presetId)
        }

        self.statusBarController.onToggleFloatingIndicator = { [weak self] in
            self?.handleToggleFloatingIndicator()
        }

        self.statusBarController.onToggleLaunchAtLogin = { [weak self] in
            self?.handleToggleLaunchAtLogin()
        }

        self.statusBarController.onOpenHistory = { [weak self] in
            self?.handleOpenHistory()
        }

        self.statusBarController.onShowApp = { [weak self] in
            self?.handleShowApp()
        }

        self.statusBarController.onSelectModel = { [weak self] modelName in
            self?.handleSelectModel(modelName)
        }

        self.statusBarController.onCheckForUpdates = { [weak self] in
            self?.handleCheckForUpdates()
        }

        self.statusBarController.setMainWindowController(mainWindowController)
        
        self.audioRecorder.onAudioLevel = { [weak self] level in
            self?.floatingIndicatorController.updateAudioLevel(level)
            self?.pillFloatingIndicatorController.updateAudioLevel(level)
        }
        
        self.floatingIndicatorController.onStopRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording(source: .floatingIndicatorStop)
            }
        }
        
        self.pillFloatingIndicatorController.onStopRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording(source: .pillIndicatorStop)
            }
        }

        self.pillFloatingIndicatorController.onCancelRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleClearAudioBuffer()
            }
        }

        self.pillFloatingIndicatorController.onStartRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording(source: .pillIndicatorStart)
            }
        }

        setupHotkeys()
        observeSettings()
        setupEscapeKeyMonitor()
        setupModifierKeyMonitor()
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .switchModel,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let modelName = notification.userInfo?["modelName"] as? String else {
                return
            }
            Task {
                await self.switchToModel(named: modelName)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .requestActiveModel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let activeModel = self.activeModelName else { return }
            NotificationCenter.default.post(
                name: .modelActiveChanged,
                object: nil,
                userInfo: ["modelName": activeModel]
            )
        }
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
            return
        }

        seedBuiltInPresetsIfNeeded()
        refreshStatusBarPresets()

        splashController.show()
        
        await startNormalOperation()
        
        splashController.dismiss { [weak self] in
            self?.mainWindowController.show()
        }
    }
    
    private func showOnboarding() {
        onboardingController.showOnboarding(
            settings: settingsStore,
            modelManager: modelManager,
            transcriptionService: transcriptionService,
            permissionManager: permissionManager,
            onComplete: { [weak self] in
                Task { @MainActor in
                    await self?.finishPostOnboardingSetup()
                    self?.mainWindowController.show()
                    self?.showWelcomePopoverAfterDelay()
                }
            }
        )
    }
    
    private func showWelcomePopoverAfterDelay() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            statusBarController.showWelcomePopover()
        }
    }
    
    private func finishPostOnboardingSetup() async {
        seedBuiltInPresetsIfNeeded()
        refreshStatusBarPresets()
        registerHotkeysFromSettings()

        ensureAccessibilityPermissionForDirectInsert(trigger: "post-onboarding", showFallbackAlert: false)
    }
    
    private func seedBuiltInPresetsIfNeeded() {
        do {
            try promptPresetStore.seedBuiltInPresets()
            Log.app.debug("Synced built-in prompt presets")
        } catch {
            Log.app.error("Failed to seed built-in presets: \(error)")
        }
    }

    private func refreshStatusBarPresets() {
        do {
            let presets = try promptPresetStore.fetchAll()
            let mapped = presets.map { (id: $0.id.uuidString, name: $0.name) }
            statusBarController.updatePromptPresets(mapped)
        } catch {
            Log.app.error("Failed to refresh status bar presets: \(error)")
        }
    }
    
    private func startNormalOperation() async {
        // Sync launch at login state on startup
        let actualLaunchAtLoginState = launchAtLoginManager.isEnabled
        if settingsStore.launchAtLogin != actualLaunchAtLoginState {
            settingsStore.launchAtLogin = actualLaunchAtLoginState
            Log.app.info("Synced launch at login state: \(actualLaunchAtLoginState)")
        }

        let micStatus = permissionManager.checkPermissionStatus()
        if micStatus == .denied || micStatus == .restricted {
            Log.app.warning("Microphone permission denied - recording will not work")
            AlertManager.shared.showMicrophonePermissionAlert()
        } else if micStatus == .notDetermined {
            Log.app.info("Microphone permission not determined at launch; request deferred until recording starts")
        }

        ensureAccessibilityPermissionForDirectInsert(trigger: "startup", showFallbackAlert: false)

        let modelName = settingsStore.selectedModel
        
        await modelManager.refreshDownloadedModels()
        let modelExists = modelManager.isModelDownloaded(modelName)
        
        if modelExists {
            splashController.setLoading("Loading model...")
            Log.model.info("Model \(modelName) found, loading...")
            do {
                let model = modelManager.availableModels.first { $0.name == modelName }
                let provider = model?.provider ?? .whisperKit
                try await transcriptionService.loadModel(modelName: modelName, provider: provider)
                Log.model.info("Model loaded successfully")
                self.activeModelName = modelName
                NotificationCenter.default.post(name: .modelActiveChanged, object: nil, userInfo: ["modelName": modelName])
            } catch {
                self.error = error
                Log.app.error("Failed to load transcription model: \(error)")
                
                // Check if this is a timeout error
                let errorMessage = (error as? LocalizedError)?.errorDescription ?? ""
                if errorMessage.contains("timed out") {
                    AlertManager.shared.showModelTimeoutAlert()
                }
            }
        } else {
            // Model missing - check if any model is available for fallback
            let downloadedModels = await modelManager.getDownloadedModels()
            
            if let fallbackModel = downloadedModels.first {
                Log.model.info("Selected model \(modelName) not found, falling back to \(fallbackModel.name)")
                splashController.setLoading("Using \(fallbackModel.displayName)...")
                settingsStore.selectedModel = fallbackModel.name
                do {
                    let provider = fallbackModel.provider
                    try await transcriptionService.loadModel(modelName: fallbackModel.name, provider: provider)
                    Log.model.info("Fallback model loaded successfully")
                    self.activeModelName = fallbackModel.name
                    NotificationCenter.default.post(name: .modelActiveChanged, object: nil, userInfo: ["modelName": fallbackModel.name])
                } catch {
                    self.error = error
                    Log.app.error("Failed to load fallback model: \(error)")
                    
                    let errorMessage = (error as? LocalizedError)?.errorDescription ?? ""
                    if errorMessage.contains("timed out") {
                        AlertManager.shared.showModelTimeoutAlert()
                    }
                }
            } else {
                // No models available - download the selected one
                splashController.setDownloading("Downloading \(modelName)...")
                Log.model.info("Model \(modelName) not found, downloading...")
                
                do {
                    try await modelManager.downloadModel(named: modelName) { [weak self] progress in
                        Task { @MainActor in
                            self?.splashController.updateProgress(progress)
                        }
                    }
                    splashController.setLoading("Loading model...")
                    Log.model.info("Model downloaded, loading...")
                    let downloadedModel = modelManager.availableModels.first { $0.name == modelName }
                    let provider = downloadedModel?.provider ?? .whisperKit
                    try await transcriptionService.loadModel(modelName: modelName, provider: provider)
                    Log.model.info("Model loaded successfully")
                    self.activeModelName = modelName
                    NotificationCenter.default.post(name: .modelActiveChanged, object: nil, userInfo: ["modelName": modelName])
                } catch {
                    self.error = error
                    Log.app.error("Failed to download/load model: \(error)")
                    
                    let errorMessage = (error as? LocalizedError)?.errorDescription ?? ""
                    if errorMessage.contains("timed out") {
                        AlertManager.shared.showModelTimeoutAlert()
                    }
                }
            }
        }

        // Load recent transcripts for the menu
        updateRecentTranscriptsMenu()
        
        if settingsStore.floatingIndicatorEnabled &&
           settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
            pillFloatingIndicatorController.showTab()
        }
    }

    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        registerHotkeysFromSettings()
    }
    
    private func registerHotkeysFromSettings() {
        hotkeyManager.unregisterAll()
        
        guard HotkeyRegistrationState.shouldRegisterHotkeys(hasCompletedOnboarding: settingsStore.hasCompletedOnboarding) else {
            Log.hotkey.info("Skipping hotkey registration until onboarding is complete")
            return
        }

        var registrationState = HotkeyRegistrationState()
        
        if !settingsStore.pushToTalkHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.pushToTalkHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.pushToTalkHotkeyModifiers))

            if canRegisterHotkey(
                identifier: "push-to-talk",
                displayName: "Push-to-Talk",
                hotkeyString: settingsStore.pushToTalkHotkey,
                keyCode: keyCode,
                modifiers: modifiers,
                registrationState: &registrationState
            ) {
                _ = hotkeyManager.registerHotkey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    identifier: "push-to-talk",
                    mode: .pushToTalk,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handlePushToTalkStart()
                        }
                    },
                    onKeyUp: { [weak self] in
                        Task { @MainActor in
                            await self?.handlePushToTalkEnd()
                        }
                    }
                )
            }
        }
        
        if !settingsStore.toggleHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.toggleHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.toggleHotkeyModifiers))

            if canRegisterHotkey(
                identifier: "toggle-recording",
                displayName: "Toggle Recording",
                hotkeyString: settingsStore.toggleHotkey,
                keyCode: keyCode,
                modifiers: modifiers,
                registrationState: &registrationState
            ) {
                _ = hotkeyManager.registerHotkey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    identifier: "toggle-recording",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleToggleRecording(source: .hotkeyToggle)
                        }
                    },
                    onKeyUp: nil
                )
            }
        }

        if !settingsStore.copyLastTranscriptHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.copyLastTranscriptHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.copyLastTranscriptHotkeyModifiers))

            Log.hotkey.info("Registering copy-last-transcript: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.copyLastTranscriptHotkey)")

            if canRegisterHotkey(
                identifier: "copy-last-transcript",
                displayName: "Copy Last Transcript",
                hotkeyString: settingsStore.copyLastTranscriptHotkey,
                keyCode: keyCode,
                modifiers: modifiers,
                registrationState: &registrationState
            ) {
                _ = hotkeyManager.registerHotkey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    identifier: "copy-last-transcript",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleCopyLastTranscript()
                        }
                    },
                    onKeyUp: nil
                )
            }
        }

        if !settingsStore.quickCapturePTTHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.quickCapturePTTHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.quickCapturePTTHotkeyModifiers))

            Log.hotkey.info("Registering quick-capture-ptt: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCapturePTTHotkey)")

            if canRegisterHotkey(
                identifier: "quick-capture-ptt",
                displayName: "Note Capture (Push-to-Talk)",
                hotkeyString: settingsStore.quickCapturePTTHotkey,
                keyCode: keyCode,
                modifiers: modifiers,
                registrationState: &registrationState
            ) {
                _ = hotkeyManager.registerHotkey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    identifier: "quick-capture-ptt",
                    mode: .pushToTalk,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleQuickCapturePTTStart()
                        }
                    },
                    onKeyUp: { [weak self] in
                        Task { @MainActor in
                            await self?.handleQuickCapturePTTEnd()
                        }
                    }
                )
            }
        }

        if !settingsStore.quickCaptureToggleHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.quickCaptureToggleHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.quickCaptureToggleHotkeyModifiers))

            Log.hotkey.info("Registering quick-capture-toggle: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCaptureToggleHotkey)")

            if canRegisterHotkey(
                identifier: "quick-capture-toggle",
                displayName: "Note Capture (Toggle)",
                hotkeyString: settingsStore.quickCaptureToggleHotkey,
                keyCode: keyCode,
                modifiers: modifiers,
                registrationState: &registrationState
            ) {
                _ = hotkeyManager.registerHotkey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    identifier: "quick-capture-toggle",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleQuickCaptureToggle()
                        }
                    },
                    onKeyUp: nil
                )
            }
        }
    }

    private func canRegisterHotkey(
        identifier: String,
        displayName: String,
        hotkeyString: String,
        keyCode: UInt32,
        modifiers: HotkeyManager.ModifierFlags,
        registrationState: inout HotkeyRegistrationState
    ) -> Bool {
        if let conflict = registrationState.register(
            identifier: identifier,
            keyCode: keyCode,
            modifiers: modifiers.rawValue
        ) {
            let existingDisplayName = hotkeyDisplayName(for: conflict.existingIdentifier)
            let conflictKey = conflict.conflictKey

            Log.hotkey.error(
                "Hotkey conflict detected for \(hotkeyString, privacy: .public): \(existingDisplayName, privacy: .public) conflicts with \(displayName, privacy: .public). Ignoring \(displayName, privacy: .public)"
            )

            if !reportedHotkeyConflicts.contains(conflictKey) {
                reportedHotkeyConflicts.insert(conflictKey)
                AlertManager.shared.showHotkeyConflictAlert(
                    hotkey: hotkeyString,
                    firstAction: existingDisplayName,
                    secondAction: displayName
                )
            }

            return false
        }

        return true
    }

    private func hotkeyDisplayName(for identifier: String) -> String {
        switch identifier {
        case "toggle-recording":
            return "Toggle Recording"
        case "push-to-talk":
            return "Push-to-Talk"
        case "copy-last-transcript":
            return "Copy Last Transcript"
        case "quick-capture-ptt":
            return "Note Capture (Push-to-Talk)"
        case "quick-capture-toggle":
            return "Note Capture (Toggle)"
        default:
            return identifier
        }
    }
    
    // MARK: - Settings Observation
    
    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }

                    let outputModeValue = self.settingsStore.outputMode
                    let didOutputModeChange = outputModeValue != self.lastObservedOutputMode
                    self.lastObservedOutputMode = outputModeValue

                    let mode: OutputMode = outputModeValue == "clipboard" ? .clipboard : .directInsert
                    self.outputManager.setOutputMode(mode)

                    if mode == .directInsert && didOutputModeChange {
                        self.ensureAccessibilityPermissionForDirectInsert(trigger: "settings-change", showFallbackAlert: true)
                    }
                    
                    self.audioRecorder.setPreferredInputDeviceUID(self.settingsStore.selectedInputDeviceUID)
                    
                    self.updateFloatingIndicatorVisibility()

                    self.registerHotkeysFromSettings()
                    self.statusBarController.updateDynamicItems()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateFloatingIndicatorVisibility() {
        guard !isRecording && !isProcessing else { return }
        
        if settingsStore.floatingIndicatorEnabled &&
           settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
            pillFloatingIndicatorController.showTab()
        } else {
            pillFloatingIndicatorController.hide()
        }
    }
    
    // MARK: - Recording Flow
    
    private func handlePushToTalkStart() async {
        guard !isRecording && !isProcessing else { return }
        
        do {
            try await startRecording(source: .hotkeyPushToTalk)
        } catch {
            self.error = error
            audioRecorder.resetAudioEngine()
            Log.app.error("Failed to start recording: \(error)")
        }
    }
    
    private func handlePushToTalkEnd() async {
        guard isRecording else { return }
        
        do {
            try await stopRecordingAndTranscribe()
        } catch {
            self.error = error
            audioRecorder.resetAudioEngine()
            Log.app.error("Failed to stop recording: \(error)")
        }
    }

    // MARK: - Quick Capture Handlers (Push-to-Talk)

    private func handleQuickCapturePTTStart() async {
        guard !isRecording && !isProcessing else { return }

        isQuickCaptureMode = true
        quickCaptureTranscription = nil

        do {
            try await startRecording(source: .hotkeyQuickCapturePTT)
        } catch {
            self.error = error
            isQuickCaptureMode = false
            audioRecorder.resetAudioEngine()
            Log.app.error("Failed to start quick capture recording: \(error)")
        }
    }

    private func handleQuickCapturePTTEnd() async {
        guard isRecording && isQuickCaptureMode else { return }

        do {
            if let enhancedNote = try await stopRecordingAndTranscribeForQuickCapture() {
                openNoteEditorWithEnhancedNote(enhancedNote)
            }
        } catch {
            self.error = error
            audioRecorder.resetAudioEngine()
            Log.app.error("Failed to stop quick capture recording: \(error)")
        }

        isQuickCaptureMode = false
    }

    // MARK: - Quick Capture Handlers (Toggle)

    private func handleQuickCaptureToggle() async {
        if isRecording && isQuickCaptureMode {
            do {
                if let enhancedNote = try await stopRecordingAndTranscribeForQuickCapture() {
                    openNoteEditorWithEnhancedNote(enhancedNote)
                }
            } catch {
                self.error = error
                audioRecorder.resetAudioEngine()
                Log.app.error("Failed to stop quick capture recording: \(error)")
            }
            isQuickCaptureMode = false
        } else if !isRecording && !isProcessing {
            isQuickCaptureMode = true
            quickCaptureTranscription = nil

            do {
                try await startRecording(source: .hotkeyQuickCaptureToggle)
            } catch {
                self.error = error
                isQuickCaptureMode = false
                audioRecorder.resetAudioEngine()
                Log.app.error("Failed to start quick capture recording: \(error)")
            }
        }
    }

    private func stopRecordingAndTranscribeForQuickCapture() async throws -> AIEnhancementService.EnhancedNote? {
        guard recordingStartTime != nil else {
            Log.app.warning("stopRecordingAndTranscribeForQuickCapture called but recordingStartTime is nil")
            return nil
        }

        isRecording = false
        isProcessing = true
        var didResetProcessingState = false

        statusBarController.setProcessingState()

        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.stopRecording()
            } else {
                floatingIndicatorController.stopRecording()
            }
        }

        defer {
            if !didResetProcessingState {
                resetProcessingState()
            }
        }

        let audioData: Data
        do {
            audioData = try await audioRecorder.stopRecording()
        } catch {
            Log.app.error("Failed to stop recording: \(error)")
            throw error
        }

        guard !audioData.isEmpty else {
            Log.app.warning("No audio data recorded")
            return nil
        }

        let transcribedText: String
        do {
            transcribedText = try await transcriptionService.transcribe(audioData: audioData)
        } catch let error as TranscriptionService.TranscriptionError {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            if case .modelNotLoaded = error {
                AlertManager.shared.showModelNotLoadedAlert()
            } else {
                AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            }
            throw error
        } catch {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            throw error
        }

        let (textAfterReplacements, appliedReplacements) = try dictionaryStore.applyReplacements(to: transcribedText)
        self.lastAppliedReplacements = appliedReplacements

        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           let apiKey = settingsStore.apiKey {
            do {
                var notePrompt = settingsStore.noteEnhancementPrompt

                let vocabularyWords = try dictionaryStore.fetchAllVocabularyWords()
                if !vocabularyWords.isEmpty {
                    let wordList = vocabularyWords.map { $0.word }.joined(separator: ", ")
                    notePrompt += "\n\nUser's vocabulary includes: \(wordList)"
                }

                if !lastAppliedReplacements.isEmpty {
                    let replacementList = lastAppliedReplacements
                        .map { "'\($0.original)' → '\($0.replacement)'" }
                        .joined(separator: ", ")
                    notePrompt += "\n\nNote: These automatic replacements were applied: \(replacementList). Please preserve these corrections."
                }

                let existingTags = (try? notesStore.getAllUniqueTags()) ?? []
                let enhancedNote = try await aiEnhancementService.enhanceNote(
                    content: textAfterReplacements,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    contentPrompt: notePrompt,
                    generateMetadata: true,
                    existingTags: existingTags
                )
                Log.app.info("Note enhancement completed: title='\(enhancedNote.title)', tags=\(enhancedNote.tags.count)")
                return enhancedNote
            } catch {
                Log.app.error("Note enhancement failed: \(error)")
            }
        }

        let fallbackTitle = aiEnhancementService.generateFallbackTitle(from: textAfterReplacements)
        return AIEnhancementService.EnhancedNote(
            content: textAfterReplacements,
            title: fallbackTitle,
            tags: []
        )
    }

    private func openNoteEditorWithEnhancedNote(_ enhancedNote: AIEnhancementService.EnhancedNote) {
        let newNote = NoteSchema.Note(
            title: enhancedNote.title,
            content: enhancedNote.content,
            tags: enhancedNote.tags,
            sourceTranscriptionID: nil
        )

        noteEditorWindowController.show(note: newNote, isNewNote: true)

        Log.app.info("Opened note editor with enhanced note")
    }

    private func handleToggleRecording(source: RecordingTriggerSource) async {
        if isRecording {
            do {
                try await stopRecordingAndTranscribe()
            } catch {
                self.error = error
                audioRecorder.resetAudioEngine()
                Log.app.error("Failed to stop recording: \(error)")
            }
        } else if !isProcessing {
            do {
                try await startRecording(source: source)
            } catch {
                self.error = error
                audioRecorder.resetAudioEngine()
                Log.app.error("Failed to start recording: \(error)")
            }
        }
    }
    
    private func startRecording(source: RecordingTriggerSource) async throws {
        logRecordingStartAttempt(source: source)

        // If permissions were granted after launch, recreate global event taps
        // so escape-to-cancel and modifier tracking become available mid-session.
        ensureGlobalKeyMonitorsIfPossible()

        let didStartRecording: Bool
        do {
            didStartRecording = try await audioRecorder.startRecording()
        } catch {
            Log.app.error("Audio engine failed to start: \(error)")
            throw error
        }

        guard didStartRecording else {
            Log.app.debug("Recording start already in progress; ignoring duplicate start request")
            return
        }
        
        isRecording = true
        recordingStartTime = Date()
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil

        if settingsStore.enableClipboardContext || settingsStore.enableUIContext {
            let clipboardText = settingsStore.enableClipboardContext ? contextCaptureService.captureClipboardText() : nil
            capturedContext = CapturedContext(clipboardText: clipboardText)

            // Capture AX-based UI context when enabled (non-blocking)
            var appContext: AppContextInfo? = nil
            var captureWarnings: [ContextCaptureWarning] = []
            if settingsStore.enableUIContext {
                let result = contextEngineService.captureAppContext()
                appContext = result.appContext
                captureWarnings = result.warnings
                if !captureWarnings.isEmpty {
                    Log.app.debug("UI context capture warnings: \(captureWarnings.map(\.localizedDescription).joined(separator: ", "))")
                }
                if let ctx = appContext {
                    Log.app.info("Captured UI context: app=\(ctx.appName), window=\(ctx.windowTitle ?? "nil")")
                }
            }

            capturedSnapshot = ContextSnapshot(
                timestamp: Date(),
                appContext: appContext,
                clipboardText: clipboardText,
                warnings: captureWarnings
            )

            if let snapshot = capturedSnapshot {
                let routingSignal = PromptRoutingSignal.from(
                    snapshot: snapshot,
                    adapterRegistry: appContextAdapterRegistry
                )
                capturedRoutingSignal = routingSignal
                _ = promptRoutingResolver.resolve(signal: routingSignal)

                if let bundleIdentifier = snapshot.appContext?.bundleIdentifier {
                    let adapter = appContextAdapterRegistry.adapter(for: bundleIdentifier)
                    capturedAdapterCapabilities = adapter.capabilities
                    let caps = adapter.capabilities
                    Log.context.info("Adapter context: app=\(caps.displayName) prefix=\(caps.mentionPrefix) fileMentions=\(caps.supportsFileMentions) codeContext=\(caps.supportsCodeContext) docsMentions=\(caps.supportsDocsMentions) diffContext=\(caps.supportsDiffContext) webContext=\(caps.supportsWebContext) chatHistory=\(caps.supportsChatHistory)")
                }
            }
        }

        statusBarController.setRecordingState()

        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.expandForRecording()
            } else {
                floatingIndicatorController.startRecording()
            }
        }
    }

    private func logRecordingStartAttempt(source: RecordingTriggerSource) {
        recordingStartAttemptCounter += 1
        let snapshot = permissionManager.microphoneAuthorizationSnapshot()
        let shortVersion = Bundle.main.appShortVersionString
        let buildVersion = Bundle.main.appBuildVersionString
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path
        let executablePath = Bundle.main.executableURL?.path ?? "unknown"
        let cachedDecision = snapshot.cachedDecision.map { $0 ? "granted" : "denied" } ?? "none"

        Log.app.info(
            "recording_start_attempt id=\(self.recordingStartAttemptCounter) source=\(source.rawValue, privacy: .public) resolved=\(String(describing: snapshot.resolvedStatus), privacy: .public) avaudio=\(snapshot.audioApplicationStatus, privacy: .public) avcapture=\(snapshot.captureDeviceStatus, privacy: .public) requestedThisLaunch=\(snapshot.hasRequestedThisLaunch) cachedDecision=\(cachedDecision, privacy: .public) bundleId=\(bundleIdentifier, privacy: .public) shortVersion=\(shortVersion, privacy: .public) buildVersion=\(buildVersion, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier) onboardingCompleted=\(self.settingsStore.hasCompletedOnboarding) bundlePath=\(bundlePath, privacy: .public) executablePath=\(executablePath, privacy: .public)"
        )
    }
    
    private func stopRecordingAndTranscribe() async throws {
        guard let startTime = recordingStartTime else {
            Log.app.warning("stopRecordingAndTranscribe called but recordingStartTime is nil")
            return
        }

        isRecording = false
        isProcessing = true
        var didResetProcessingState = false

        statusBarController.setProcessingState()
        
        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.stopRecording()
            } else {
                floatingIndicatorController.stopRecording()
            }
        }
        
        defer {
            if !didResetProcessingState {
                resetProcessingState()
            }
        }

        let audioData: Data
        do {
            audioData = try await audioRecorder.stopRecording()
        } catch {
            Log.app.error("Failed to stop recording: \(error)")
            throw error
        }
        
        guard !audioData.isEmpty else {
            Log.app.warning("No audio data recorded")
            return
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let transcribedText: String
        do {
            transcribedText = try await transcriptionService.transcribe(audioData: audioData)
        } catch let error as TranscriptionService.TranscriptionError {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            if case .modelNotLoaded = error {
                AlertManager.shared.showModelNotLoadedAlert()
            } else {
                AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            }
            throw error
        } catch {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            throw error
        }
        
        let (textAfterReplacements, appliedReplacements) = try dictionaryStore.applyReplacements(to: transcribedText)
        self.lastAppliedReplacements = appliedReplacements
        
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }
        
        // Mention rewrite: resolve spoken file mentions to app-specific syntax
        // Runs whenever adapter supports file mentions AND workspace roots are derivable
        // (not gated by isCodeEditorContext — enables Antigravity and other non-IDE adapters)
        var textAfterMentions = textAfterReplacements
        var derivedWorkspaceRoots: [String] = []
        if let workspacePath = capturedRoutingSignal?.workspacePath {
            derivedWorkspaceRoots.append(workspacePath)
        } else if let docPath = capturedSnapshot?.appContext?.documentPath, !docPath.isEmpty {
            let parent = (docPath as NSString).deletingLastPathComponent
            if !parent.isEmpty {
                derivedWorkspaceRoots.append(parent)
            }
        }

        if let capabilities = capturedAdapterCapabilities,
           capabilities.supportsFileMentions {
            if !derivedWorkspaceRoots.isEmpty {
                let rewriteResult = await mentionRewriteService.rewrite(
                    text: textAfterReplacements,
                    capabilities: capabilities,
                    workspaceRoots: derivedWorkspaceRoots,
                    activeDocumentPath: capturedSnapshot?.appContext?.documentPath
                )
                textAfterMentions = rewriteResult.text
                if rewriteResult.didRewrite {
                    Log.app.info("Mention rewrite: \(rewriteResult.rewrittenCount) mention(s) rewritten, \(rewriteResult.preservedCount) preserved")
                }
            } else {
                let adapterName = capturedAdapterCapabilities?.displayName ?? "unknown"
                let hasDocPath = capturedSnapshot?.appContext?.documentPath != nil
                Log.app.warning("Adapter '\(adapterName)' supports file mentions but no workspace roots derived (documentPath available: \(hasDocPath)); skipping mention rewrite")
            }
        }
        
        var finalText = textAfterMentions
        var originalText: String? = nil
        var enhancedWithModel: String? = nil

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           let apiKey = settingsStore.apiKey {
            do {
                originalText = textAfterMentions
                Log.app.info("AI enhancement enabled, saving original text before enhancement")
                
                var basePrompt: String
                if let presetId = settingsStore.selectedPresetId,
                   let presetUUID = UUID(uuidString: presetId),
                   let allPresets = try? promptPresetStore.fetchAll(),
                   let selectedPreset = allPresets.first(where: { $0.id == presetUUID }) {
                    basePrompt = selectedPreset.prompt
                } else {
                    basePrompt = settingsStore.aiEnhancementPrompt ?? AIEnhancementService.defaultSystemPrompt
                }
                
                // Add vocabulary section if exists
                let vocabularyWords = try dictionaryStore.fetchAllVocabularyWords()
                if !vocabularyWords.isEmpty {
                    let wordList = vocabularyWords.map { $0.word }.joined(separator: ", ")
                    basePrompt += "\n\nUser's vocabulary includes: \(wordList)"
                }
                
                // Add replacements section if applied
                if !lastAppliedReplacements.isEmpty {
                    let replacementList = lastAppliedReplacements
                        .map { "'\($0.original)' → '\($0.replacement)'" }
                        .joined(separator: ", ")
                    basePrompt += "\n\nNote: These automatic replacements were applied to the transcription: \(replacementList). Please preserve these corrections."
                }
                
                var contextMetadata = AIEnhancementService.ContextMetadata.none
                var clipboardText: String? = nil

                var workspaceTreeSummary: String? = nil
                if !derivedWorkspaceRoots.isEmpty {
                    workspaceTreeSummary = await mentionRewriteService.generateWorkspaceTreeSummary(
                        workspaceRoots: derivedWorkspaceRoots,
                        activeDocumentPath: capturedSnapshot?.appContext?.documentPath
                    )
                }
                
                if let context = capturedContext {
                    let hasClipboardText = context.clipboardText != nil && !context.clipboardText!.isEmpty
                    clipboardText = hasClipboardText ? context.clipboardText : nil
                    
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: hasClipboardText,
                        clipboardText: clipboardText,
                        hasClipboardImage: false,
                        appContext: capturedSnapshot?.appContext,
                        adapterCapabilities: capturedAdapterCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary
                    )
                } else if let appContext = capturedSnapshot?.appContext {
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: false,
                        clipboardText: nil,
                        hasClipboardImage: false,
                        appContext: appContext,
                        adapterCapabilities: capturedAdapterCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary
                    )
                }

                finalText = try await aiEnhancementService.enhance(
                    text: textAfterMentions,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    customPrompt: basePrompt,
                    imageBase64: nil,
                    context: contextMetadata
                )
                capturedContext = nil
                capturedSnapshot = nil
                capturedAdapterCapabilities = nil
                capturedRoutingSignal = nil
                enhancedWithModel = settingsStore.aiModel
                Log.app.info("AI enhancement completed, original: \(textAfterMentions.count) chars, enhanced: \(finalText.count) chars")
            } catch {
                Log.app.error("AI enhancement failed: \(error)")
                AlertManager.shared.showAIEnhancementErrorAlert(error: error)
                originalText = nil
            }
        } else {
            if !settingsStore.aiEnhancementEnabled {
                Log.app.debug("AI enhancement disabled, no original text to save")
            } else if settingsStore.apiEndpoint == nil {
                Log.app.debug("AI enhancement enabled but no API endpoint configured")
            } else if settingsStore.apiKey == nil {
                Log.app.debug("AI enhancement enabled but no API key configured")
            }
        }

        do {
            if outputManager.outputMode == .directInsert {
                ensureAccessibilityPermissionForDirectInsert(trigger: "output", showFallbackAlert: true)
            }

            let outputText = settingsStore.addTrailingSpace ? finalText + " " : finalText
            try await outputManager.output(outputText)
        } catch {
            Log.app.error("Output failed: \(error)")
        }

        do {
            try historyStore.save(
                text: finalText,
                originalText: originalText,
                duration: duration,
                modelUsed: settingsStore.selectedModel,
                enhancedWith: enhancedWithModel
            )
            updateRecentTranscriptsMenu()
        } catch {
            Log.app.error("Failed to save to history: \(error)")
        }
    }
    
    // MARK: - Escape Key Cancellation
    
    private func setupEscapeKeyMonitor() {
        if escapeEventTap != nil, escapeRunLoopSource != nil {
            installEscapeGlobalMonitorFallbackIfNeeded()
            return
        }

        if escapeEventTap != nil, escapeRunLoopSource == nil {
            Log.app.warning("Escape event tap missing run loop source; recreating monitor")
            escapeEventTap = nil
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                let coordinator = Unmanaged<AppCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                return coordinator.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.app.error("Failed to create CGEventTap - Accessibility or Input Monitoring permission may be required")
            installEscapeGlobalMonitorFallbackIfNeeded()
            return
        }

        installEscapeGlobalMonitorFallbackIfNeeded()
        
        escapeEventTap = eventTap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            Log.app.error("Failed to create run loop source for escape CGEventTap")
            escapeEventTap = nil
            return
        }

        escapeRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Log.app.info("Escape key monitor installed")
    }

    private func setupModifierKeyMonitor() {
        if modifierEventTap != nil, modifierRunLoopSource != nil {
            removeModifierGlobalMonitorFallbackIfNeeded()
            return
        }

        if modifierEventTap != nil, modifierRunLoopSource == nil {
            Log.hotkey.warning("Modifier event tap missing run loop source; recreating monitor")
            modifierEventTap = nil
        }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let coordinator = Unmanaged<AppCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                return coordinator.handleModifierKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("Failed to create modifier CGEventTap - Accessibility or Input Monitoring permission may be required")
            installModifierGlobalMonitorFallbackIfNeeded()
            return
        }

        removeModifierGlobalMonitorFallbackIfNeeded()

        modifierEventTap = eventTap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            Log.hotkey.error("Failed to create run loop source for modifier CGEventTap")
            modifierEventTap = nil
            return
        }

        modifierRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Log.hotkey.info("Modifier key monitor installed")
    }

    private func installEscapeGlobalMonitorFallbackIfNeeded() {
        guard escapeGlobalMonitor == nil else { return }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.handleEscapeSignal(source: "nsevent-global")
            }
        }

        if escapeGlobalMonitor != nil {
            Log.app.warning("Using NSEvent global monitor fallback for escape key")
        }
    }

    private func removeEscapeGlobalMonitorFallbackIfNeeded() {
        guard let monitor = escapeGlobalMonitor else { return }
        NSEvent.removeMonitor(monitor)
        escapeGlobalMonitor = nil
        Log.app.debug("Removed NSEvent global monitor fallback for escape key")
    }

    private func installModifierGlobalMonitorFallbackIfNeeded() {
        guard modifierGlobalMonitor == nil else { return }

        modifierGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let cgEvent = event.cgEvent else { return }
            Task { @MainActor in
                self?.hotkeyManager.handleModifierFlagsChanged(event: cgEvent)
            }
        }

        if modifierGlobalMonitor != nil {
            Log.hotkey.warning("Using NSEvent global monitor fallback for modifier changes")
        }
    }

    private func removeModifierGlobalMonitorFallbackIfNeeded() {
        guard let monitor = modifierGlobalMonitor else { return }
        NSEvent.removeMonitor(monitor)
        modifierGlobalMonitor = nil
        Log.hotkey.debug("Removed NSEvent global monitor fallback for modifier changes")
    }
    
    private nonisolated func handleKeyEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let disabledType = type
            Task { @MainActor in
                if let tap = self.escapeEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    Log.app.warning("Escape key monitor was disabled (type=\(disabledType.rawValue)); re-enabled")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else { return Unmanaged.passUnretained(event) }
        
        Task { @MainActor in
            self.handleEscapeSignal(source: "cg-event-tap")
        }
        
        return Unmanaged.passUnretained(event)
    }

    private func handleEscapeSignal(source: String) {
        let now = Date()
        if let lastSignal = lastEscapeSignalTime,
           now.timeIntervalSince(lastSignal) <= duplicateEscapeSignalThreshold {
            Log.app.debug("Ignoring duplicate escape signal from \(source)")
            return
        }

        lastEscapeSignalTime = now
        Log.app.info("Escape signal received (source=\(source))")
        handleEscapeKeyPress()
    }

    private nonisolated func handleModifierKeyEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let disabledType = type
            Task { @MainActor in
                if let tap = self.modifierEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    Log.hotkey.warning("Modifier key monitor was disabled (type=\(disabledType.rawValue)); re-enabled")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

        Task { @MainActor in
            hotkeyManager.handleModifierFlagsChanged(event: event)
        }
        return Unmanaged.passUnretained(event)
    }
    
    private func handleEscapeKeyPress() {
        guard isRecording || isProcessing else { return }
        
        let now = Date()
        
        if let lastTime = lastEscapeTime,
           now.timeIntervalSince(lastTime) <= doubleEscapeThreshold {
            lastEscapeTime = nil
            floatingIndicatorController.clearEscapePrimed()
            cancelCurrentOperation()
        } else {
            lastEscapeTime = now
            if settingsStore.floatingIndicatorEnabled {
                floatingIndicatorController.showEscapePrimed()
            }
        }
    }
    
    private func cancelCurrentOperation() {
        guard isRecording || isProcessing else {
            Log.app.debug("Double-escape pressed but no operation in progress")
            return
        }
        
        Log.app.info("Cancelling current operation via double-escape")
        
        audioRecorder.resetAudioEngine()
        isRecording = false
        isProcessing = false
        recordingStartTime = nil
        capturedContext = nil
        capturedSnapshot = nil
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil
        error = nil

        statusBarController.setIdleState()
        statusBarController.updateMenuState()
        
        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.finishProcessing()
            } else {
                floatingIndicatorController.finishProcessing()
            }
        }
    }

    private func resetProcessingState() {
        isProcessing = false
        recordingStartTime = nil
        capturedContext = nil
        capturedSnapshot = nil
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil
        statusBarController.setIdleState()
        statusBarController.updateMenuState()

        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.finishProcessing()
            } else {
                floatingIndicatorController.finishProcessing()
            }
        }
    }

    // MARK: - Copy Last Transcript

    private func handleCopyLastTranscript() async {
        do {
            let records = try historyStore.fetch(limit: 1)
            guard let lastRecord = records.first else {
                Log.app.warning("No transcripts to copy")
                return
            }

            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([lastRecord.text as NSString])
            }
            Log.app.info("Copied last transcript to clipboard")
        } catch {
            Log.app.error("Failed to copy last transcript: \(error)")
        }
    }

    // MARK: - Export Last Transcript

    private func handleExportLastTranscript() async {
        do {
            let records = try historyStore.fetch(limit: 1)
            guard let lastRecord = records.first else {
                Log.app.warning("No transcripts to export")
                return
            }

            await MainActor.run {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.plainText]
                savePanel.nameFieldStringValue = "transcript.txt"
                savePanel.title = "Export Transcript"

                guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

                do {
                    try lastRecord.text.write(to: url, atomically: true, encoding: .utf8)
                    Log.app.info("Exported transcript to \(url.lastPathComponent)")
                } catch {
                    Log.app.error("Failed to export transcript: \(error)")
                }
            }
        } catch {
            Log.app.error("Failed to fetch transcript for export: \(error)")
        }
    }

    // MARK: - Clear Audio Buffer

    private func handleClearAudioBuffer() async {
        guard isRecording else { return }

        Log.app.info("Clearing audio buffer")
        audioRecorder.cancelRecording()
        isRecording = false
        recordingStartTime = nil

        statusBarController.setIdleState()

        if settingsStore.floatingIndicatorEnabled {
            if settingsStore.floatingIndicatorType == FloatingIndicatorType.pill.rawValue {
                pillFloatingIndicatorController.finishProcessing()
            } else {
                floatingIndicatorController.stopRecording()
            }
        }
    }

    // MARK: - Cancel Operation

    private func handleCancelOperation() async {
        cancelCurrentOperation()
    }

    // MARK: - Toggle Output Mode

    private func handleToggleOutputMode() {
        let newMode = settingsStore.outputMode == "clipboard" ? "directInsert" : "clipboard"
        settingsStore.outputMode = newMode
        Log.app.info("Output mode changed to: \(newMode)")
    }

    private func ensureAccessibilityPermissionForDirectInsert(trigger: String, showFallbackAlert: Bool) {
        guard outputManager.outputMode == .directInsert else { return }

        let hasPermission = permissionManager.checkAccessibilityPermission()
        if hasPermission {
            hasShownAccessibilityFallbackAlertThisLaunch = false
            ensureGlobalKeyMonitorsIfPossible()
            return
        }

        if !hasRequestedAccessibilityPermissionThisLaunch {
            hasRequestedAccessibilityPermissionThisLaunch = true

            let grantedImmediately = permissionManager.requestAccessibilityPermission(showPrompt: true)
            Log.app.info("Requested Accessibility permission (trigger=\(trigger), grantedImmediately=\(grantedImmediately))")

            permissionManager.refreshAccessibilityPermissionStatus()
        }

        let hasPermissionAfterRequest = permissionManager.checkAccessibilityPermission()
        if hasPermissionAfterRequest {
            hasShownAccessibilityFallbackAlertThisLaunch = false
            ensureGlobalKeyMonitorsIfPossible()
            return
        }

        Log.app.info("Accessibility permission not granted - direct insert will use clipboard fallback")

        if showFallbackAlert && !hasShownAccessibilityFallbackAlertThisLaunch {
            hasShownAccessibilityFallbackAlertThisLaunch = true
            AlertManager.shared.showAccessibilityPermissionAlert()
        }

    }

    private func ensureGlobalKeyMonitorsIfPossible() {
        guard permissionManager.checkAccessibilityPermission() else { return }

        setupEscapeKeyMonitor()
        setupModifierKeyMonitor()
    }

    // MARK: - Toggle AI Enhancement

    private func handleToggleAIEnhancement() {
        settingsStore.aiEnhancementEnabled.toggle()
        let status = settingsStore.aiEnhancementEnabled ? "enabled" : "disabled"
        Log.app.info("AI enhancement \(status)")
    }

    // MARK: - Select Prompt Preset

    private func handleSelectPromptPreset(_ presetId: String?) {
        settingsStore.selectedPresetId = presetId

        if let presetId = presetId,
           let presetUUID = UUID(uuidString: presetId),
           let allPresets = try? promptPresetStore.fetchAll(),
           let selectedPreset = allPresets.first(where: { $0.id == presetUUID }) {
            settingsStore.aiEnhancementPrompt = selectedPreset.prompt
            Log.app.info("Prompt preset changed to: \(selectedPreset.name)")
        } else {
            Log.app.info("Prompt preset changed to: Custom")
        }

        statusBarController.updateDynamicItems()
    }

    // MARK: - Toggle Floating Indicator

    private func handleToggleFloatingIndicator() {
        settingsStore.floatingIndicatorEnabled.toggle()
        let status = settingsStore.floatingIndicatorEnabled ? "enabled" : "disabled"
        Log.app.info("Floating indicator \(status)")
    }

    // MARK: - Toggle Launch at Login

    private func handleToggleLaunchAtLogin() {
        let newValue = !settingsStore.launchAtLogin
        do {
            try launchAtLoginManager.setEnabled(newValue)
            settingsStore.launchAtLogin = newValue
            let status = newValue ? "enabled" : "disabled"
            Log.app.info("Launch at login \(status)")
        } catch {
            Log.app.error("Failed to toggle launch at login: \(error)")
        }
    }

    private func handleCheckForUpdates() {
        if updateService.shouldDeferUpdate(isRecording: isRecording || isProcessing) {
            AlertManager.shared.showGenericErrorAlert(
                title: "Update Deferred",
                message: "Finish recording or processing before checking for updates."
            )
            return
        }

        updateService.checkForUpdates()
    }

    // MARK: - Open History

    private func handleOpenHistory() {
        mainWindowController.showHistory()
    }

    // MARK: - Show App

    private func handleShowApp() {
        mainWindowController.show()
    }

    // MARK: - Select Model
    
    private func handleSelectModel(_ modelName: String) {
        settingsStore.selectedModel = modelName
        Log.app.info("Default model changed to: \(modelName)")
    }
    
    func switchToModel(named modelName: String) async {
        guard modelName != activeModelName else {
            Log.app.info("Model \(modelName) is already active")
            return
        }
        
        guard !isRecording && !isProcessing else {
            Log.app.warning("Cannot switch model while recording or processing")
            return
        }
        
        Log.app.info("Switching to model: \(modelName)")
        
        await modelManager.refreshDownloadedModels()
        guard let model = modelManager.availableModels.first(where: { $0.name == modelName }) else {
            Log.app.error("Cannot switch to model \(modelName): not found")
            return
        }
        
        if !modelManager.isModelDownloaded(modelName) {
            Log.app.error("Cannot switch to model \(modelName): not downloaded")
            return
        }
        
        splashController.setLoading("Switching to \(model.displayName)...")
        
        do {
            let provider = model.provider
            try await transcriptionService.loadModel(modelName: modelName, provider: provider)
            self.activeModelName = modelName
            NotificationCenter.default.post(name: .modelActiveChanged, object: nil, userInfo: ["modelName": modelName])
            Log.model.info("Switched to model \(modelName) successfully")
        } catch {
            Log.app.error("Failed to switch model: \(error)")
            self.error = error
            AlertManager.shared.showModelLoadErrorAlert(error: error)
        }
    }
    
    // MARK: - Update Recent Transcripts

    private func updateRecentTranscriptsMenu() {
        Task {
            do {
                let records = try historyStore.fetch(limit: 5)
                let transcripts = records.map { (id: $0.id, text: $0.text, timestamp: $0.timestamp) }
                await MainActor.run {
                    statusBarController.updateRecentTranscripts(transcripts)
                }
            } catch {
                Log.app.error("Failed to update recent transcripts: \(error)")
            }
        }
    }

    func cleanup() {
        if let eventTap = escapeEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let source = escapeRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            escapeEventTap = nil
            escapeRunLoopSource = nil
        }

        if let eventTap = modifierEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let source = modifierRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            modifierEventTap = nil
            modifierRunLoopSource = nil
        }
    }
}
