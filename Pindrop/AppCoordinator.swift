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
import AVFoundation
import AppKit
import os.log

private final class EventTapRunLoopThread: Thread {

    private let readinessSemaphore = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var runLoop: CFRunLoop?
    private let keepAlivePort = Port()

    init(name: String) {
        super.init()
        self.name = name
        self.qualityOfService = .userInteractive
    }

    override func main() {
        let currentRunLoop = CFRunLoopGetCurrent()

        stateLock.lock()
        runLoop = currentRunLoop
        stateLock.unlock()

        RunLoop.current.add(keepAlivePort, forMode: .default)
        readinessSemaphore.signal()

        while !isCancelled {
            autoreleasepool {
                _ = RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }

        stateLock.lock()
        runLoop = nil
        stateLock.unlock()
    }

    func performAndWait(_ block: @escaping (CFRunLoop) -> Void) {
        startIfNeeded()

        guard let runLoop = currentRunLoop else { return }
        guard let defaultMode = CFRunLoopMode.defaultMode else { return }

        let completionSemaphore = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, defaultMode.rawValue as CFTypeRef) {
            block(runLoop)
            completionSemaphore.signal()
        }
        CFRunLoopWakeUp(runLoop)
        completionSemaphore.wait()
    }

    func stopIfNeeded() {
        guard let runLoop = currentRunLoop else { return }
        guard let defaultMode = CFRunLoopMode.defaultMode else { return }

        let completionSemaphore = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, defaultMode.rawValue as CFTypeRef) {
            CFRunLoopStop(runLoop)
            completionSemaphore.signal()
        }
        CFRunLoopWakeUp(runLoop)
        completionSemaphore.wait()
        cancel()
    }

    private func startIfNeeded() {
        guard !isExecuting && !isFinished else { return }
        start()
        readinessSemaphore.wait()
    }

    private var currentRunLoop: CFRunLoop? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runLoop
    }
}

extension Notification.Name {
    static let switchModel = Notification.Name("tech.watzon.pindrop.switchModel")
    static let modelActiveChanged = Notification.Name("tech.watzon.pindrop.modelActiveChanged")
    static let requestActiveModel = Notification.Name("tech.watzon.pindrop.requestActiveModel")
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

struct HotkeyBindingSnapshot: Equatable {
    let hotkey: String
    let keyCode: Int
    let modifiers: Int
}

struct HotkeySettingsSnapshot: Equatable {
    let hasCompletedOnboarding: Bool
    let pushToTalk: HotkeyBindingSnapshot
    let toggle: HotkeyBindingSnapshot
    let copyLastTranscript: HotkeyBindingSnapshot
    let quickCapturePTT: HotkeyBindingSnapshot
    let quickCaptureToggle: HotkeyBindingSnapshot
}

struct SettingsObservationSnapshot: Equatable {
    let outputMode: String
    let automaticDictionaryLearningEnabled: Bool
    let selectedInputDeviceUID: String
    let selectedAppLanguage: AppLanguage
    let floatingIndicatorEnabled: Bool
    let floatingIndicatorType: FloatingIndicatorType
    let aiEnhancementEnabled: Bool
    let enableUIContext: Bool
    let vibeLiveSessionEnabled: Bool
    let hotkeys: HotkeySettingsSnapshot
}

@MainActor
@Observable
final class AppCoordinator {

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["PINDROP_TEST_MODE"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private enum RecordingTriggerSource: String {
        case statusBarMenu = "status-bar-menu"
        case hotkeyToggle = "hotkey-toggle"
        case hotkeyPushToTalk = "hotkey-push-to-talk"
        case hotkeyQuickCapturePTT = "hotkey-quick-capture-ptt"
        case hotkeyQuickCaptureToggle = "hotkey-quick-capture-toggle"
        case floatingIndicatorStart = "floating-indicator-start"
        case floatingIndicatorStop = "floating-indicator-stop"
        case pillIndicatorStop = "pill-indicator-stop"
        case pillIndicatorStart = "pill-indicator-start"
        case bubbleIndicatorStart = "bubble-indicator-start"
        case bubbleIndicatorStop = "bubble-indicator-stop"
    }

    enum EventTapRecoveryAction: Equatable {
        case reenable
        case recreate
    }

    struct EventTapRecoveryDecision: Equatable {
        let consecutiveDisableCount: Int
        let action: EventTapRecoveryAction
    }

    static func determineEventTapRecovery(
        now: Date,
        lastDisableAt: Date?,
        consecutiveDisableCount: Int,
        disableLoopWindow: TimeInterval,
        maxReenableAttemptsBeforeRecreate: Int
    ) -> EventTapRecoveryDecision {
        let decision = KMPTranscriptionBridge.determineEventTapRecovery(
            elapsedSinceLastDisable: lastDisableAt.map { now.timeIntervalSince($0) },
            consecutiveDisableCount: consecutiveDisableCount,
            disableLoopWindow: disableLoopWindow,
            maxReenableAttemptsBeforeRecreate: maxReenableAttemptsBeforeRecreate
        )

        return EventTapRecoveryDecision(
            consecutiveDisableCount: decision.consecutiveDisableCount,
            action: decision.action == .recreate ? .recreate : .reenable
        )
    }

    private enum EventTapKind {
        case escape
        case modifier
    }

    private struct EventTapDisableState {
        var lastDisableAt: Date?
        var consecutiveDisableCount = 0
        var lastDisabledTypeRawValue: UInt32?
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
    let toastService: ToastService
    let automaticDictionaryLearningService: AutomaticDictionaryLearningService
    let promptPresetStore: PromptPresetStore
    let mentionRewriteService: MentionRewriteService
    let mediaPauseService: MediaPauseService
    let mediaIngestionService: MediaIngestionService
    let mediaPreparationService: MediaPreparationService
    let mediaTranscriptionState: MediaTranscriptionFeatureState

    // MARK: - UI Controllers
    
    let statusBarController: StatusBarController
    let floatingIndicatorState: FloatingIndicatorState
    let floatingIndicatorController: FloatingIndicatorController
    let pillFloatingIndicatorController: PillFloatingIndicatorController
    let caretBubbleFloatingIndicatorController: CaretBubbleFloatingIndicatorController
    let floatingIndicatorPresenters: [FloatingIndicatorType: any FloatingIndicatorPresenting]
    let onboardingController: OnboardingWindowController
    let splashController: SplashWindowController
    let mainWindowController: MainWindowController
    let noteEditorWindowController: NoteEditorWindowController
    let toastWindowController: ToastWindowController
    
    // MARK: - Quick Capture State
    
    private var isQuickCaptureMode = false
    private var quickCaptureTranscription: String?
    private var isStreamingTranscriptionSessionActive = false
    private var streamingAudioProcessingTask: Task<Void, Never>?
    private var streamingInsertionUpdateTask: Task<Void, Never>?
    private var mediaTranscriptionTask: Task<Void, Never>?
    
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
    private var contextSessionState: ContextSessionState?
    private var contextSessionPollTimer: Timer?
    private var contextSessionAppActivationObserver: NSObjectProtocol?
    private var lastFocusOrWindowUpdateAt: Date?
    private let contextSessionPollInterval: TimeInterval = 1.25
    private let contextSessionFocusUpdateThrottle: TimeInterval = 0.75
    private var recordingStartAttemptCounter: UInt64 = 0
    private var reportedHotkeyConflicts = Set<String>()
    private let appContextAdapterRegistry = AppContextAdapterRegistry()
    private let promptRoutingResolver: any PromptRoutingResolver = NoOpPromptRoutingResolver()
    private let enableSystemHooks: Bool
    private var lastObservedSettingsSnapshot: SettingsObservationSnapshot?
    private var hasRequestedAccessibilityPermissionThisLaunch = false
    private var hasShownAccessibilityFallbackAlertThisLaunch = false
    private var floatingIndicatorHiddenUntil: Date?
    private var floatingIndicatorHiddenTask: Task<Void, Never>?
    private var activeFloatingIndicatorType: FloatingIndicatorType?

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
    private let eventTapRunLoopThread = EventTapRunLoopThread(name: "tech.watzon.pindrop.event-tap-runloop")
    private var escapeEventTapDisableState = EventTapDisableState()
    private var modifierEventTapDisableState = EventTapDisableState()
    private var escapeEventTapRecoveryTask: Task<Void, Never>?
    private var modifierEventTapRecoveryTask: Task<Void, Never>?
    private var lastEscapeTime: Date?
    private var lastEscapeSignalTime: Date?
    private let doubleEscapeThreshold: TimeInterval = 0.4
    private let duplicateEscapeSignalThreshold: TimeInterval = 0.08
    private let eventTapRecoveryDelay: Duration = .milliseconds(250)
    private let eventTapDisableLoopWindow: TimeInterval = 1.0
    private let maxEventTapReenableAttemptsBeforeRecreate = 3
    
    // MARK: - Initialization
    
    init(
        modelContext: ModelContext,
        modelContainer: ModelContainer,
        enableSystemHooks: Bool? = nil
    ) {
        self.enableSystemHooks = enableSystemHooks ?? !Self.isRunningTests
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
        self.audioRecorder.setPreferredInputDeviceUID(settingsStore.selectedInputDeviceUID)
        
        let initialOutputMode: OutputMode = settingsStore.outputMode == "directInsert" ? .directInsert : .clipboard
        self.outputManager = OutputManager(outputMode: initialOutputMode)
        self.historyStore = HistoryStore(modelContext: modelContext)
        self.dictionaryStore = DictionaryStore(modelContext: modelContext)
        self.notesStore = NotesStore(modelContext: modelContext, aiEnhancementService: aiEnhancementService, settingsStore: settingsStore)
        self.contextCaptureService = ContextCaptureService()
        self.contextEngineService = ContextEngineService()
        self.toastWindowController = ToastWindowController()
        self.toastService = ToastService(presenter: toastWindowController)
        self.automaticDictionaryLearningService = AutomaticDictionaryLearningService(
            snapshotProvider: contextEngineService,
            dictionaryStore: dictionaryStore,
            toastService: toastService
        )
        self.promptPresetStore = PromptPresetStore(modelContext: modelContext)
        self.mentionRewriteService = MentionRewriteService()
        self.mediaPauseService = MediaPauseService()
        self.mediaIngestionService = MediaIngestionService()
        self.mediaPreparationService = MediaPreparationService()
        self.mediaTranscriptionState = MediaTranscriptionFeatureState()

        self.statusBarController = StatusBarController(
            audioRecorder: audioRecorder,
            settingsStore: settingsStore
        )
        self.floatingIndicatorState = FloatingIndicatorState()
        self.floatingIndicatorController = FloatingIndicatorController(state: floatingIndicatorState)
        self.pillFloatingIndicatorController = PillFloatingIndicatorController(
            state: floatingIndicatorState,
            settingsStore: settingsStore
        )
        self.caretBubbleFloatingIndicatorController = CaretBubbleFloatingIndicatorController(state: floatingIndicatorState)
        self.floatingIndicatorPresenters = [
            .notch: floatingIndicatorController,
            .pill: pillFloatingIndicatorController,
            .bubble: caretBubbleFloatingIndicatorController
        ]
        self.onboardingController = OnboardingWindowController()
        let splashState = SplashScreenState()
        self.splashController = SplashWindowController(state: splashState)
        self.mainWindowController = MainWindowController()
        self.mainWindowController.setModelContainer(modelContainer)
        self.noteEditorWindowController = NoteEditorWindowController()
        self.noteEditorWindowController.setModelContainer(modelContainer)
        self.mainWindowController.configureTranscribeFeature(
            state: mediaTranscriptionState,
            modelManager: modelManager,
            settingsStore: settingsStore,
            onImportMediaFiles: { [weak self] urls in
                self?.handleImportMediaFiles(urls)
            },
            onSubmitMediaLink: { [weak self] link in
                self?.handleSubmitMediaLink(link)
            },
            onDownloadDiarizationModel: { [weak self] in
                self?.handleDownloadDiarizationModel()
            }
        )

        self.statusBarController.onToggleRecording = { [weak self] in
            await self?.handleToggleRecording(source: .statusBarMenu)
        }

        self.statusBarController.onCopyLastTranscript = { [weak self] in
            await self?.handleCopyLastTranscript()
        }

        self.statusBarController.onPasteLastTranscript = { [weak self] in
            await self?.handlePasteLastTranscript()
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


        self.statusBarController.onReportIssue = { [weak self] in
            self?.handleReportIssue()
        }

        self.statusBarController.onSelectInputDeviceUID = { [weak self] uid in
            self?.handleSelectInputDeviceUID(uid)
        }

        self.statusBarController.onSelectLanguage = { [weak self] language in
            self?.handleSelectLanguage(language)
        }

        self.statusBarController.onShowApp = { [weak self] in
            self?.handleShowApp()
        }

        self.statusBarController.onSelectModel = { [weak self] modelName in
            Task { @MainActor in
                await self?.switchToModel(named: modelName)
            }
        }

        self.statusBarController.onMenuWillOpen = { [weak self] in
            await self?.refreshStatusBarModelMenu()
        }

        self.statusBarController.onCheckForUpdates = { [weak self] in
            self?.handleCheckForUpdates()
        }

        self.statusBarController.setMainWindowController(mainWindowController)
        
        self.audioRecorder.onAudioLevel = { [weak self] level in
            self?.floatingIndicatorState.updateAudioLevel(level)
        }

        let floatingIndicatorActions = FloatingIndicatorActions(
            onStartRecording: { [weak self] type in
                Task { @MainActor in
                    await self?.handleToggleRecording(source: self?.recordingTriggerSourceForIndicatorStart(type) ?? .floatingIndicatorStart)
                }
            },
            onStopRecording: { [weak self] type in
                Task { @MainActor in
                    await self?.handleToggleRecording(source: self?.recordingTriggerSourceForIndicatorStop(type) ?? .floatingIndicatorStop)
                }
            },
            onCancelRecording: { [weak self] in
                Task { @MainActor in
                    await self?.handleCancelOperation()
                }
            },
            onHideForOneHour: { [weak self] in
                self?.handleHideFloatingIndicatorForOneHour()
            },
            onReportIssue: { [weak self] in
                self?.handleReportIssue()
            },
            onGoToSettings: { [weak self] in
                self?.statusBarController.showSettings(tab: .general)
            },
            onViewTranscriptHistory: { [weak self] in
                self?.handleOpenHistory()
            },
            onPasteLastTranscript: { [weak self] in
                await self?.handlePasteLastTranscript()
            },
            onSelectInputDeviceUID: { [weak self] uid in
                self?.handleSelectInputDeviceUID(uid)
            },
            onSelectLanguage: { [weak self] language in
                self?.handleSelectLanguage(language)
            },
            availableInputDevicesProvider: {
                AudioDeviceManager.inputDevices().map { (uid: $0.uid, displayName: $0.displayName) }
            },
            selectedInputDeviceUIDProvider: { [weak self] in
                self?.settingsStore.selectedInputDeviceUID ?? ""
            },
            selectedLanguageProvider: { [weak self] in
                self?.settingsStore.selectedAppLanguage ?? .automatic
            },
            anchorProvider: { [weak self] in
                self?.contextEngineService.captureFocusedElementAnchorRect()
            }
        )

        for presenter in self.floatingIndicatorPresenters.values {
            presenter.configure(actions: floatingIndicatorActions)
        }
        self.floatingIndicatorState.updateHotkeys(
            toggleHotkey: settingsStore.toggleHotkey,
            pushToTalkHotkey: settingsStore.pushToTalkHotkey
        )

        self.lastObservedSettingsSnapshot = currentSettingsObservationSnapshot()
        if self.enableSystemHooks {
            setupHotkeys()
            setupEscapeKeyMonitor()
            setupModifierKeyMonitor()
        } else {
            Log.app.debug("Skipping global hotkey and key monitor setup in test environment")
        }
        observeSettings()
        setupNotifications()
        Log.boot.info("AppCoordinator init finished enableSystemHooks=\(self.enableSystemHooks)")
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
            Task { @MainActor [weak self] in
                guard let self, let activeModel = self.activeModelName else { return }
                NotificationCenter.default.post(
                    name: .modelActiveChanged,
                    object: nil,
                    userInfo: ["modelName": activeModel]
                )
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        Log.boot.info("AppCoordinator.start() entered hasCompletedOnboarding=\(settingsStore.hasCompletedOnboarding) selectedModel=\(settingsStore.selectedModel)")
        if !settingsStore.hasCompletedOnboarding {
            Log.boot.info("Taking onboarding path (skipping splash and normal operation until complete)")
            showOnboarding()
            return
        }

        Log.boot.info("Taking normal startup path: seed presets, splash, startNormalOperation")
        seedBuiltInPresetsIfNeeded()
        refreshStatusBarPresets()

        splashController.show()
        
        await startNormalOperation()
        
        splashController.dismiss { [weak self] in
            self?.mainWindowController.show()
        }
        Log.boot.info("AppCoordinator.start() finished normal path")
    }
    
    private func showOnboarding() {
        Log.boot.info("showOnboarding: presenting onboarding window")
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
        Log.boot.info("finishPostOnboardingSetup begin")
        seedBuiltInPresetsIfNeeded()
        refreshStatusBarPresets()
        registerHotkeysFromSettings()

        ensureAccessibilityPermissionForDirectInsert(trigger: "post-onboarding", showFallbackAlert: false)
        updateVibeRuntimeStateFromSettings()
        Log.boot.info("finishPostOnboardingSetup complete")
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

    private func refreshStatusBarModelMenu() async {
        let downloadedModels = await modelManager.getDownloadedModels()
        let mappedModels = downloadedModels.map { (name: $0.name, displayName: $0.displayName) }
        statusBarController.updateSwitchableModels(mappedModels)
    }

    private func setActiveModel(_ modelName: String) {
        activeModelName = modelName
        statusBarController.updateSelectedModel(modelName)
        NotificationCenter.default.post(
            name: .modelActiveChanged,
            object: nil,
            userInfo: ["modelName": modelName]
        )
    }

    private func loadAndActivateModel(
        named modelName: String,
        provider: ModelManager.ModelProvider
    ) async throws {
        try await transcriptionService.loadModel(modelName: modelName, provider: provider)
        setActiveModel(modelName)
    }

    private func attemptWhisperModelRepairAndReload(
        modelName: String,
        displayName: String
    ) async throws {
        Log.boot.info("attemptWhisperModelRepairAndReload begin model=\(modelName)")
        Log.model.warning("Selected Whisper model failed to load, attempting repair for \(modelName)")

        do {
            try await modelManager.deleteModel(named: modelName)
        } catch ModelManager.ModelError.modelNotFound {
            Log.model.debug("Model \(modelName) was not present when starting repair")
        }

        splashController.setDownloading("Repairing \(displayName)...")
        try await modelManager.downloadModel(named: modelName) { [weak self] progress in
            Task { @MainActor in
                self?.splashController.updateProgress(progress)
            }
        }

        splashController.setLoading("Loading \(displayName)...")
        try await loadAndActivateModel(named: modelName, provider: .whisperKit)
        Log.boot.info("attemptWhisperModelRepairAndReload finished OK model=\(modelName)")
    }

    private func handleModelLoadError(_ error: Error, context: String) {
        self.error = error
        Log.app.error("\(context): \(error)")

        let errorMessage = (error as? LocalizedError)?.errorDescription ?? ""
        if errorMessage.contains("timed out") {
            AlertManager.shared.showModelTimeoutAlert()
        }
    }
    
    private func startNormalOperation() async {
        Log.boot.info("startNormalOperation begin")
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

        await modelManager.refreshDownloadedModels()
        let downloadedModels = await modelManager.getDownloadedModels()
        let startupModel = KMPTranscriptionBridge.resolveStartupModel(
            selectedModelId: settingsStore.selectedModel,
            defaultModelId: SettingsStore.Defaults.selectedModel,
            availableModels: modelManager.availableModels,
            downloadedModelIds: downloadedModels.map(\.name)
        )

        if settingsStore.selectedModel != startupModel.updatedSelectedModelId {
            if startupModel.action == .loadFallback {
                Log.model.info(
                    "Selected model \(settingsStore.selectedModel) not found locally, falling back to \(startupModel.updatedSelectedModelId)"
                )
            } else {
                Log.model.warning(
                    "Selected model \(settingsStore.selectedModel) is not recognized, resetting to \(startupModel.updatedSelectedModelId)"
                )
            }
            settingsStore.selectedModel = startupModel.updatedSelectedModelId
        }

        switch startupModel.action {
        case .loadSelected:
            splashController.setLoading("Loading model...")
            Log.model.info("Model \(startupModel.resolvedModel.name) found, loading...")
            do {
                try await loadAndActivateModel(
                    named: startupModel.resolvedModel.name,
                    provider: startupModel.resolvedModel.provider
                )
                Log.model.info("Model loaded successfully")
            } catch {
                if startupModel.resolvedModel.provider == .whisperKit {
                    do {
                        try await attemptWhisperModelRepairAndReload(
                            modelName: startupModel.resolvedModel.name,
                            displayName: startupModel.resolvedModel.displayName
                        )
                        Log.model.info("Model repaired and loaded successfully")
                    } catch {
                        handleModelLoadError(error, context: "Failed to repair transcription model")
                    }
                } else {
                    handleModelLoadError(error, context: "Failed to load transcription model")
                }
            }
        case .loadFallback:
            splashController.setLoading("Using \(startupModel.resolvedModel.displayName)...")
            do {
                try await loadAndActivateModel(
                    named: startupModel.resolvedModel.name,
                    provider: startupModel.resolvedModel.provider
                )
                Log.model.info("Fallback model loaded successfully")
            } catch {
                handleModelLoadError(error, context: "Failed to load fallback model")
            }
        case .downloadSelected:
            splashController.setDownloading("Downloading \(startupModel.resolvedModel.name)...")
            Log.model.info("Model \(startupModel.resolvedModel.name) not found, downloading...")

            do {
                try await modelManager.downloadModel(named: startupModel.resolvedModel.name) { [weak self] progress in
                    Task { @MainActor in
                        self?.splashController.updateProgress(progress)
                    }
                }
                splashController.setLoading("Loading model...")
                Log.model.info("Model downloaded, loading...")
                try await loadAndActivateModel(
                    named: startupModel.resolvedModel.name,
                    provider: startupModel.resolvedModel.provider
                )
                Log.model.info("Model loaded successfully")
            } catch {
                handleModelLoadError(error, context: "Failed to download/load model")
            }
        }

        // Load recent transcripts for the menu
        updateRecentTranscriptsMenu()
        await refreshStatusBarModelMenu()
        
        updateFloatingIndicatorVisibility()

        updateVibeRuntimeStateFromSettings()
        Log.boot.info("startNormalOperation complete")
    }

    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        registerHotkeysFromSettings()
    }
    
    private func registerHotkeysFromSettings() {
        guard enableSystemHooks else { return }

        hotkeyManager.unregisterAll()
        reportedHotkeyConflicts.removeAll()
        guard HotkeyRegistrationState.shouldRegisterHotkeys(hasCompletedOnboarding: settingsStore.hasCompletedOnboarding) else {
            Log.hotkey.info("Skipping hotkey registration until onboarding is complete")
            return
        }

        var registrationState = HotkeyRegistrationState()

        if !settingsStore.pushToTalkHotkey.isEmpty,
           let binding = validatedHotkeyBinding(
               displayName: "Push-to-Talk",
               hotkeyString: settingsStore.pushToTalkHotkey,
               keyCodeValue: settingsStore.pushToTalkHotkeyCode,
               modifiersValue: settingsStore.pushToTalkHotkeyModifiers
           ) {
            if canRegisterHotkey(
                identifier: "push-to-talk",
                displayName: "Push-to-Talk",
                hotkeyString: settingsStore.pushToTalkHotkey,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                registrationState: &registrationState
            ) {
                let didRegister = hotkeyManager.registerHotkey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
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

                if !didRegister {
                    handleHotkeyRegistrationFailure(displayName: "Push-to-Talk", hotkeyString: settingsStore.pushToTalkHotkey)
                }
            }
        }

        if !settingsStore.toggleHotkey.isEmpty,
           let binding = validatedHotkeyBinding(
               displayName: "Toggle Recording",
               hotkeyString: settingsStore.toggleHotkey,
               keyCodeValue: settingsStore.toggleHotkeyCode,
               modifiersValue: settingsStore.toggleHotkeyModifiers
           ) {
            if canRegisterHotkey(
                identifier: "toggle-recording",
                displayName: "Toggle Recording",
                hotkeyString: settingsStore.toggleHotkey,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                registrationState: &registrationState
            ) {
                let didRegister = hotkeyManager.registerHotkey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    identifier: "toggle-recording",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleToggleRecording(source: .hotkeyToggle)
                        }
                    },
                    onKeyUp: nil
                )

                if !didRegister {
                    handleHotkeyRegistrationFailure(displayName: "Toggle Recording", hotkeyString: settingsStore.toggleHotkey)
                }
            }
        }

        if !settingsStore.copyLastTranscriptHotkey.isEmpty,
           let binding = validatedHotkeyBinding(
               displayName: "Copy Last Transcript",
               hotkeyString: settingsStore.copyLastTranscriptHotkey,
               keyCodeValue: settingsStore.copyLastTranscriptHotkeyCode,
               modifiersValue: settingsStore.copyLastTranscriptHotkeyModifiers
           ) {
            Log.hotkey.info("Registering copy-last-transcript: keyCode=\(binding.keyCode), modifiers=0x\(String(binding.modifiers.rawValue, radix: 16)), string=\(self.settingsStore.copyLastTranscriptHotkey)")

            if canRegisterHotkey(
                identifier: "copy-last-transcript",
                displayName: "Copy Last Transcript",
                hotkeyString: settingsStore.copyLastTranscriptHotkey,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                registrationState: &registrationState
            ) {
                let didRegister = hotkeyManager.registerHotkey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    identifier: "copy-last-transcript",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleCopyLastTranscript()
                        }
                    },
                    onKeyUp: nil
                )

                if !didRegister {
                    handleHotkeyRegistrationFailure(displayName: "Copy Last Transcript", hotkeyString: settingsStore.copyLastTranscriptHotkey)
                }
            }
        }

        if !settingsStore.quickCapturePTTHotkey.isEmpty,
           let binding = validatedHotkeyBinding(
               displayName: "Note Capture (Push-to-Talk)",
               hotkeyString: settingsStore.quickCapturePTTHotkey,
               keyCodeValue: settingsStore.quickCapturePTTHotkeyCode,
               modifiersValue: settingsStore.quickCapturePTTHotkeyModifiers
           ) {
            Log.hotkey.info("Registering quick-capture-ptt: keyCode=\(binding.keyCode), modifiers=0x\(String(binding.modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCapturePTTHotkey)")

            if canRegisterHotkey(
                identifier: "quick-capture-ptt",
                displayName: "Note Capture (Push-to-Talk)",
                hotkeyString: settingsStore.quickCapturePTTHotkey,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                registrationState: &registrationState
            ) {
                let didRegister = hotkeyManager.registerHotkey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
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

                if !didRegister {
                    handleHotkeyRegistrationFailure(displayName: "Note Capture (Push-to-Talk)", hotkeyString: settingsStore.quickCapturePTTHotkey)
                }
            }
        }

        if !settingsStore.quickCaptureToggleHotkey.isEmpty,
           let binding = validatedHotkeyBinding(
               displayName: "Note Capture (Toggle)",
               hotkeyString: settingsStore.quickCaptureToggleHotkey,
               keyCodeValue: settingsStore.quickCaptureToggleHotkeyCode,
               modifiersValue: settingsStore.quickCaptureToggleHotkeyModifiers
           ) {
            Log.hotkey.info("Registering quick-capture-toggle: keyCode=\(binding.keyCode), modifiers=0x\(String(binding.modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCaptureToggleHotkey)")
            if canRegisterHotkey(
                identifier: "quick-capture-toggle",
                displayName: "Note Capture (Toggle)",
                hotkeyString: settingsStore.quickCaptureToggleHotkey,
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                registrationState: &registrationState
            ) {
                let didRegister = hotkeyManager.registerHotkey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    identifier: "quick-capture-toggle",
                    mode: .toggle,
                    onKeyDown: { [weak self] in
                        Task { @MainActor in
                            await self?.handleQuickCaptureToggle()
                        }
                    },
                    onKeyUp: nil
                )
                if !didRegister {
                    handleHotkeyRegistrationFailure(displayName: "Note Capture (Toggle)", hotkeyString: settingsStore.quickCaptureToggleHotkey)
                }
            }
    }
    }
    private func validatedHotkeyBinding(
        displayName: String,
        hotkeyString: String,
        keyCodeValue: Int,
        modifiersValue: Int
    ) -> (keyCode: UInt32, modifiers: HotkeyManager.ModifierFlags)? {
        guard let keyCode = UInt32(exactly: keyCodeValue),
              let modifiersRawValue = UInt32(exactly: modifiersValue) else {
            Log.hotkey.error("Invalid hotkey values for \(displayName): string=\(hotkeyString), keyCode=\(keyCodeValue), modifiers=\(modifiersValue)")
            AlertManager.shared.showGenericErrorAlert(
                title: "Invalid Hotkey Configuration",
                message: "The saved hotkey for \(displayName) is invalid. Re-record this hotkey in Settings."
            )
            return nil
        }
        return (keyCode: keyCode, modifiers: HotkeyManager.ModifierFlags(rawValue: modifiersRawValue))
    }
    private func handleHotkeyRegistrationFailure(displayName: String, hotkeyString: String) {
        Log.hotkey.error("Failed to register hotkey for \(displayName): \(hotkeyString)")
        AlertManager.shared.showGenericErrorAlert(
            title: "Hotkey Registration Failed",
            message: "Could not register '\(hotkeyString)' for \(displayName). Choose a different shortcut in Settings."
        )
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
                "Hotkey conflict detected for \(hotkeyString): \(existingDisplayName) conflicts with \(displayName). Ignoring \(displayName)"
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
    
    private func currentSettingsObservationSnapshot() -> SettingsObservationSnapshot {
        SettingsObservationSnapshot(
            outputMode: settingsStore.outputMode,
            automaticDictionaryLearningEnabled: settingsStore.automaticDictionaryLearningEnabled,
            selectedInputDeviceUID: settingsStore.selectedInputDeviceUID,
            selectedAppLanguage: settingsStore.selectedAppLanguage,
            floatingIndicatorEnabled: settingsStore.floatingIndicatorEnabled,
            floatingIndicatorType: settingsStore.selectedFloatingIndicatorType,
            aiEnhancementEnabled: settingsStore.aiEnhancementEnabled,
            enableUIContext: settingsStore.enableUIContext,
            vibeLiveSessionEnabled: settingsStore.vibeLiveSessionEnabled,
            hotkeys: HotkeySettingsSnapshot(
                hasCompletedOnboarding: settingsStore.hasCompletedOnboarding,
                pushToTalk: HotkeyBindingSnapshot(
                    hotkey: settingsStore.pushToTalkHotkey,
                    keyCode: settingsStore.pushToTalkHotkeyCode,
                    modifiers: settingsStore.pushToTalkHotkeyModifiers
                ),
                toggle: HotkeyBindingSnapshot(
                    hotkey: settingsStore.toggleHotkey,
                    keyCode: settingsStore.toggleHotkeyCode,
                    modifiers: settingsStore.toggleHotkeyModifiers
                ),
                copyLastTranscript: HotkeyBindingSnapshot(
                    hotkey: settingsStore.copyLastTranscriptHotkey,
                    keyCode: settingsStore.copyLastTranscriptHotkeyCode,
                    modifiers: settingsStore.copyLastTranscriptHotkeyModifiers
                ),
                quickCapturePTT: HotkeyBindingSnapshot(
                    hotkey: settingsStore.quickCapturePTTHotkey,
                    keyCode: settingsStore.quickCapturePTTHotkeyCode,
                    modifiers: settingsStore.quickCapturePTTHotkeyModifiers
                ),
                quickCaptureToggle: HotkeyBindingSnapshot(
                    hotkey: settingsStore.quickCaptureToggleHotkey,
                    keyCode: settingsStore.quickCaptureToggleHotkeyCode,
                    modifiers: settingsStore.quickCaptureToggleHotkeyModifiers
                )
            )
        )
    }
    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    guard !self.settingsStore.isApplyingHotkeyUpdate else { return }

                    let snapshot = self.currentSettingsObservationSnapshot()
                    let previousSnapshot = self.lastObservedSettingsSnapshot ?? snapshot
                    self.lastObservedSettingsSnapshot = snapshot

                    if previousSnapshot.outputMode != snapshot.outputMode {
                        let mode: OutputMode = snapshot.outputMode == "clipboard" ? .clipboard : .directInsert
                        self.outputManager.setOutputMode(mode)
                        if mode == .directInsert {
                            self.ensureAccessibilityPermissionForDirectInsert(trigger: "settings-change", showFallbackAlert: true)
                        }
                    }

                    if previousSnapshot.selectedInputDeviceUID != snapshot.selectedInputDeviceUID {
                        self.audioRecorder.setPreferredInputDeviceUID(snapshot.selectedInputDeviceUID)
                    }

                    if previousSnapshot.floatingIndicatorEnabled != snapshot.floatingIndicatorEnabled
                        || previousSnapshot.floatingIndicatorType != snapshot.floatingIndicatorType {
                        if (!previousSnapshot.floatingIndicatorEnabled && snapshot.floatingIndicatorEnabled)
                            || previousSnapshot.floatingIndicatorType != snapshot.floatingIndicatorType {
                            self.clearFloatingIndicatorTemporaryHiddenState()
                        }
                        self.updateFloatingIndicatorVisibility(previousType: previousSnapshot.floatingIndicatorType)
                    }

                    if previousSnapshot.hotkeys != snapshot.hotkeys {
                        self.registerHotkeysFromSettings()
                        self.floatingIndicatorState.updateHotkeys(
                            toggleHotkey: self.settingsStore.toggleHotkey,
                            pushToTalkHotkey: self.settingsStore.pushToTalkHotkey
                        )
                    }

                    if previousSnapshot.automaticDictionaryLearningEnabled
                        && !snapshot.automaticDictionaryLearningEnabled {
                        self.automaticDictionaryLearningService.cancelObservation()
                    }

                    if previousSnapshot.selectedAppLanguage != snapshot.selectedAppLanguage {
                        self.statusBarController.reloadLocalizedStrings()
                        self.pillFloatingIndicatorController.reloadLocalizedStrings()
                    }

                    self.statusBarController.updateDynamicItems()
                    if self.isRecording {
                        if self.shouldRunLiveContextSession() {
                            self.startLiveContextSessionIfNeeded(initialSnapshot: self.capturedSnapshot)
                        } else {
                            self.stopLiveContextSession()
                        }
                    } else if previousSnapshot.aiEnhancementEnabled != snapshot.aiEnhancementEnabled
                        || previousSnapshot.enableUIContext != snapshot.enableUIContext
                        || previousSnapshot.vibeLiveSessionEnabled != snapshot.vibeLiveSessionEnabled {
                        self.updateVibeRuntimeStateFromSettings()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateFloatingIndicatorVisibility(previousType: FloatingIndicatorType? = nil) {
        guard !isFloatingIndicatorTemporarilyHidden() else {
            hideAllFloatingIndicators()
            return
        }

        guard settingsStore.floatingIndicatorEnabled else {
            hideAllFloatingIndicators()
            return
        }

        let selectedType = configuredFloatingIndicatorType()
        
        if isRecording || isProcessing {
            if previousType != selectedType {
                let oldType = activeFloatingIndicatorType ?? previousType ?? selectedType
                if oldType != selectedType {
                    floatingIndicatorPresenters[oldType]?.hide()
                    activeFloatingIndicatorType = selectedType
                    floatingIndicatorPresenters[selectedType]?.showForCurrentState()
                }
            }
            return
        }

        hideAllFloatingIndicators(except: selectedType)
        floatingIndicatorPresenters[selectedType]?.showIdleIndicator()
    }

    private func configuredFloatingIndicatorType() -> FloatingIndicatorType {
        settingsStore.selectedFloatingIndicatorType
    }

    private func recordingTriggerSourceForIndicatorStart(_ type: FloatingIndicatorType) -> RecordingTriggerSource {
        switch type {
        case .pill:
            .pillIndicatorStart
        case .notch:
            .floatingIndicatorStart
        case .bubble:
            .bubbleIndicatorStart
        }
    }

    private func recordingTriggerSourceForIndicatorStop(_ type: FloatingIndicatorType) -> RecordingTriggerSource {
        switch type {
        case .pill:
            .pillIndicatorStop
        case .notch:
            .floatingIndicatorStop
        case .bubble:
            .bubbleIndicatorStop
        }
    }

    private func hideAllFloatingIndicators(except selectedType: FloatingIndicatorType? = nil) {
        for (type, presenter) in floatingIndicatorPresenters where type != selectedType {
            presenter.hide()
        }
    }

    private func startRecordingIndicatorSession() {
        guard settingsStore.floatingIndicatorEnabled else { return }

        let selectedType = configuredFloatingIndicatorType()
        activeFloatingIndicatorType = selectedType
        hideAllFloatingIndicators(except: selectedType)
        floatingIndicatorPresenters[selectedType]?.startRecording()
    }

    private func transitionRecordingIndicatorToProcessing() {
        guard settingsStore.floatingIndicatorEnabled else {
            finishIndicatorSession()
            return
        }

        let activeType = activeFloatingIndicatorType ?? configuredFloatingIndicatorType()
        floatingIndicatorPresenters[activeType]?.transitionToProcessing()
    }

    private func startProcessingIndicatorSession() {
        guard settingsStore.floatingIndicatorEnabled else { return }
        startRecordingIndicatorSession()
        transitionRecordingIndicatorToProcessing()
    }

    private func finishIndicatorSession() {
        for presenter in floatingIndicatorPresenters.values {
            presenter.finishProcessing()
        }
        activeFloatingIndicatorType = nil

        guard settingsStore.floatingIndicatorEnabled else {
            hideAllFloatingIndicators()
            return
        }
        updateFloatingIndicatorVisibility()
    }

    private func isFloatingIndicatorTemporarilyHidden() -> Bool {
        guard let hiddenUntil = floatingIndicatorHiddenUntil else { return false }
        if Date() >= hiddenUntil {
            floatingIndicatorHiddenUntil = nil
            return false
        }
        return true
    }

    private func clearFloatingIndicatorTemporaryHiddenState() {
        floatingIndicatorHiddenUntil = nil
        floatingIndicatorHiddenTask?.cancel()
        floatingIndicatorHiddenTask = nil
    }

    // MARK: - Live Session Context

    private func shouldRunLiveContextSession() -> Bool {
        KMPTranscriptionBridge.shouldRunLiveContextSession(
            aiEnhancementEnabled: settingsStore.aiEnhancementEnabled,
            uiContextEnabled: settingsStore.enableUIContext,
            liveSessionEnabled: settingsStore.vibeLiveSessionEnabled
        )
    }

    private func updateVibeRuntimeStateFromSettings() {
        guard settingsStore.aiEnhancementEnabled else {
            settingsStore.updateVibeRuntimeState(.degraded, detail: "AI enhancement is disabled.")
            return
        }

        guard settingsStore.enableUIContext else {
            settingsStore.updateVibeRuntimeState(.degraded, detail: "Vibe mode is disabled.")
            return
        }

        guard settingsStore.vibeLiveSessionEnabled else {
            settingsStore.updateVibeRuntimeState(.limited, detail: "Live session updates are disabled.")
            return
        }

        if let contextSessionState {
            let detail = contextEngineService.deriveRuntimeDetail(
                for: contextSessionState.latestSnapshot,
                runtimeState: contextSessionState.runtimeState
            )
            settingsStore.updateVibeRuntimeState(contextSessionState.runtimeState, detail: detail)
            return
        }

        if permissionManager.checkAccessibilityPermission() {
            settingsStore.updateVibeRuntimeState(.ready, detail: "Ready for live session context.")
        } else {
            settingsStore.updateVibeRuntimeState(.limited, detail: "Accessibility permission not granted. Using limited context.")
        }
    }

    private func deriveWorkspaceRoots(
        routingSignal: PromptRoutingSignal?,
        snapshot: ContextSnapshot?
    ) -> [String] {
        var roots: [String] = []

        if let workspacePath = routingSignal?.workspacePath,
           !workspacePath.isEmpty {
            roots.append(workspacePath)
        } else if let documentPath = snapshot?.appContext?.documentPath,
                  !documentPath.isEmpty {
            let parent = (documentPath as NSString).deletingLastPathComponent
            if !parent.isEmpty {
                roots.append(parent)
            }
        }

        return mergeUniqueContextSignals(roots)
    }

    private func mentionRewriteWorkspaceDebugSummary(
        adapterName: String,
        routingSignal: PromptRoutingSignal?,
        snapshot: ContextSnapshot?,
        derivedWorkspaceRoots: [String]
    ) -> String {
        let appContext = snapshot?.appContext
        return """
        adapter=\(adapterName) bundle=\(routingSignal?.appBundleIdentifier ?? "nil") app=\(appContext?.appName ?? "nil") signalWorkspacePresent=\(hasUsableContextValue(routingSignal?.workspacePath)) documentPathPresent=\(hasUsableContextValue(appContext?.documentPath)) windowTitlePresent=\(hasUsableContextValue(appContext?.windowTitle)) focusedValuePresent=\(hasUsableContextValue(appContext?.focusedElementValue)) terminalProvider=\(routingSignal?.terminalProviderIdentifier ?? "nil") isCodeEditorContext=\(routingSignal?.isCodeEditorContext ?? false) derivedWorkspaceRootCount=\(derivedWorkspaceRoots.count)
        """
    }

    private func hasUsableContextValue(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !value.isEmpty
    }

    private func mergeUniqueContextSignals(_ groups: [String]..., limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for group in groups {
            for value in group {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                if seen.insert(normalized).inserted {
                    merged.append(normalized)
                }
                if merged.count >= limit {
                    return merged
                }
            }
        }

        return merged
    }

    private func buildSessionTransitionSignature(
        snapshot: ContextSnapshot,
        activeFilePath: String?,
        workspacePath: String?
    ) -> String {
        let signature = snapshot.transitionSignature
        return [
            signature.bundleIdentifier,
            signature.windowTitle,
            signature.focusedElementRole,
            signature.documentPath,
            signature.selectedText,
            activeFilePath,
            workspacePath
        ]
        .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        .joined(separator: "|")
    }

    private func shouldAppendTransition(
        signature: String,
        trigger: ContextSessionUpdateTrigger,
        in session: ContextSessionState
    ) -> Bool {
        KMPTranscriptionBridge.shouldAppendTransition(
            signature: signature,
            trigger: trigger.rawValue,
            lastSignature: session.transitions.last?.transitionSignature
        )
    }

    private func currentLiveSessionContext() -> AIEnhancementService.LiveSessionContext? {
        guard let contextSessionState else { return nil }

        let enrichment = contextSessionState.latestAdapterEnrichment
        let latestTransition = contextSessionState.transitions.last

        let fileTagCandidates = mergeUniqueContextSignals(
            enrichment?.fileTagCandidates ?? [],
            contextSessionState.transitions.compactMap { $0.activeFilePath },
            contextSessionState.transitions.flatMap { $0.contextTags }
        )

        return AIEnhancementService.LiveSessionContext(
            runtimeState: contextSessionState.runtimeState,
            latestAppName: contextSessionState.latestSnapshot.appContext?.appName,
            latestWindowTitle: contextSessionState.latestSnapshot.appContext?.windowTitle,
            activeFilePath: latestTransition?.activeFilePath ?? enrichment?.activeFilePath ?? contextSessionState.latestSnapshot.appContext?.documentPath,
            activeFileConfidence: latestTransition?.activeFileConfidence ?? enrichment?.activeFileConfidence ?? 0,
            workspacePath: latestTransition?.workspacePath ?? contextSessionState.latestRoutingSignal.workspacePath ?? enrichment?.workspacePath,
            workspaceConfidence: latestTransition?.workspaceConfidence ?? enrichment?.workspaceConfidence ?? 0,
            fileTagCandidates: fileTagCandidates,
            styleSignals: enrichment?.styleSignals ?? [],
            codingSignals: enrichment?.codingSignals ?? [],
            transitions: contextSessionState.transitions
        ).bounded()
    }

    private func startLiveContextSessionIfNeeded(initialSnapshot: ContextSnapshot?) {
        guard isRecording else { return }
        guard shouldRunLiveContextSession() else {
            stopLiveContextSession()
            updateVibeRuntimeStateFromSettings()
            return
        }

        installContextSessionObserversIfNeeded()

        if contextSessionPollTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: contextSessionPollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.isRecording, self.shouldRunLiveContextSession() else { return }
                    await self.updateContextSession(trigger: .poll)
                }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            contextSessionPollTimer = timer
        }

        if contextSessionState == nil {
            Task { @MainActor in
                await self.updateContextSession(trigger: .recordingStart, snapshotOverride: initialSnapshot)
            }
        }
    }

    private func stopLiveContextSession() {
        contextSessionPollTimer?.invalidate()
        contextSessionPollTimer = nil
        removeContextSessionObserversIfNeeded()
        contextSessionState = nil
        lastFocusOrWindowUpdateAt = nil
    }
    private func suspendLiveContextSessionUpdates() {
        contextSessionPollTimer?.invalidate()
        contextSessionPollTimer = nil
        removeContextSessionObserversIfNeeded()
    }

    private func installContextSessionObserversIfNeeded() {
        guard contextSessionAppActivationObserver == nil else { return }

        contextSessionAppActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isRecording, self.shouldRunLiveContextSession() else { return }
                await self.updateContextSession(trigger: .frontmostAppChange)
            }
        }
    }

    private func removeContextSessionObserversIfNeeded() {
        if let contextSessionAppActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(contextSessionAppActivationObserver)
            self.contextSessionAppActivationObserver = nil
        }
    }

    private func scheduleFocusOrWindowContextRefreshIfNeeded() {
        guard isRecording, shouldRunLiveContextSession() else { return }

        let now = Date()
        if let lastFocusOrWindowUpdateAt,
           now.timeIntervalSince(lastFocusOrWindowUpdateAt) < contextSessionFocusUpdateThrottle {
            return
        }

        lastFocusOrWindowUpdateAt = now
        Task { @MainActor in
            await self.updateContextSession(trigger: .focusOrWindowChange)
        }
    }

    private func updateContextSession(
        trigger: ContextSessionUpdateTrigger,
        snapshotOverride: ContextSnapshot? = nil
    ) async {
        guard isRecording else { return }
        guard settingsStore.enableUIContext else { return }

        let clipboardText = settingsStore.enableClipboardContext ? capturedContext?.clipboardText : nil
        let snapshot = snapshotOverride ?? contextEngineService.captureSnapshot(clipboardText: clipboardText)
        capturedSnapshot = snapshot

        let routingSignal = PromptRoutingSignal.from(
            snapshot: snapshot,
            adapterRegistry: appContextAdapterRegistry
        )
        capturedRoutingSignal = routingSignal
        _ = promptRoutingResolver.resolve(signal: routingSignal)

        var adapterCapabilities: AppAdapterCapabilities?
        var adapterEnrichment: AppRuntimeEnrichment?

        if let bundleIdentifier = snapshot.appContext?.bundleIdentifier {
            let adapter = appContextAdapterRegistry.adapter(for: bundleIdentifier)
            adapterCapabilities = adapter.capabilities
            adapterEnrichment = appContextAdapterRegistry.enrichment(for: snapshot, routingSignal: routingSignal)
        }

        capturedAdapterCapabilities = adapterCapabilities

        let workspaceRoots = deriveWorkspaceRoots(routingSignal: routingSignal, snapshot: snapshot)
        let workspaceInsights = await mentionRewriteService.deriveWorkspaceInsights(
            workspaceRoots: workspaceRoots,
            activeDocumentPath: snapshot.appContext?.documentPath
        )

        let activeFilePath = workspaceInsights.activeDocumentRelativePath
            ?? adapterEnrichment?.activeFilePath
            ?? snapshot.appContext?.documentPath

        let activeFileConfidence = max(
            workspaceInsights.activeDocumentConfidence,
            adapterEnrichment?.activeFileConfidence ?? 0
        )

        let workspacePath = routingSignal.workspacePath
            ?? workspaceInsights.normalizedWorkspaceRoots.first
            ?? adapterEnrichment?.workspacePath

        let workspaceConfidence = max(
            workspaceInsights.workspaceConfidence,
            adapterEnrichment?.workspaceConfidence ?? 0
        )

        let contextTags = mergeUniqueContextSignals(
            workspaceInsights.fileTagCandidates,
            adapterEnrichment?.fileTagCandidates ?? [],
            adapterEnrichment?.styleSignals ?? [],
            adapterEnrichment?.codingSignals ?? []
        )

        let transitionSignature = buildSessionTransitionSignature(
            snapshot: snapshot,
            activeFilePath: activeFilePath,
            workspacePath: workspacePath
        )

        let runtimeState = contextEngineService.deriveRuntimeState(
            for: snapshot,
            adapterCapabilities: adapterCapabilities
        )

        let transition = ContextSessionTransition(
            timestamp: snapshot.timestamp,
            trigger: trigger,
            snapshot: snapshot,
            activeFilePath: activeFilePath,
            activeFileConfidence: activeFileConfidence,
            workspacePath: workspacePath,
            workspaceConfidence: workspaceConfidence,
            outputMode: settingsStore.outputMode,
            contextTags: contextTags,
            transitionSignature: transitionSignature
        )

        if var contextSessionState {
            contextSessionState.latestSnapshot = snapshot
            contextSessionState.latestRoutingSignal = routingSignal
            contextSessionState.latestAdapterCapabilities = adapterCapabilities
            contextSessionState.latestAdapterEnrichment = adapterEnrichment
            contextSessionState.runtimeState = runtimeState

            if shouldAppendTransition(
                signature: transitionSignature,
                trigger: trigger,
                in: contextSessionState
            ) {
                contextSessionState.appendTransition(transition)
            }

            self.contextSessionState = contextSessionState
        } else {
            self.contextSessionState = ContextSessionState(
                startedAt: recordingStartTime ?? Date(),
                latestSnapshot: snapshot,
                latestRoutingSignal: routingSignal,
                latestAdapterCapabilities: adapterCapabilities,
                latestAdapterEnrichment: adapterEnrichment,
                runtimeState: runtimeState,
                transitions: [transition]
            )
        }

        let runtimeDetail = contextEngineService.deriveRuntimeDetail(
            for: snapshot,
            runtimeState: runtimeState
        )
        settingsStore.updateVibeRuntimeState(runtimeState, detail: runtimeDetail)
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
            handleRecordingStartFailure(error, source: .hotkeyPushToTalk)
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
            handleRecordingStartFailure(error, source: .hotkeyQuickCapturePTT)
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
                handleRecordingStartFailure(error, source: .hotkeyQuickCaptureToggle)
            }
        }
    }

    private func stopRecordingAndTranscribeForQuickCapture() async throws -> AIEnhancementService.EnhancedNote? {
        guard recordingStartTime != nil else {
            Log.app.warning("stopRecordingAndTranscribeForQuickCapture called but recordingStartTime is nil")
            return nil
        }

        isRecording = false
        mediaPauseService.endRecordingSession()
        suspendLiveContextSessionUpdates()
        isProcessing = true
        statusBarController.setProcessingState()

        transitionRecordingIndicatorToProcessing()

        defer {
            resetProcessingState()
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
            handleNoSpeechDetected(context: "quick-capture")
            return nil
        }

        let diarizationEnabled = Self.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: settingsStore.diarizationFeatureEnabled,
            isStreamingSessionActive: false
        )
        Log.app.info("Quick capture speaker diarization \(diarizationEnabled ? "enabled" : "disabled")")

        let transcriptionOutput: TranscriptionOutput
        do {
            transcriptionOutput = try await transcriptionService.transcribe(
                audioData: audioData,
                diarizationEnabled: diarizationEnabled,
                options: TranscriptionOptions(language: settingsStore.selectedAppLanguage)
            )
        } catch let error as TranscriptionService.TranscriptionError {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            let message = if case .modelNotLoaded = error {
                "No model loaded. Please download a model in Settings."
            } else {
                "Transcription failed: \(error.localizedDescription)"
            }
            toastService.show(
                ToastPayload(message: message, style: .error)
            )
            throw error
        } catch {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            toastService.show(
                ToastPayload(message: "Transcription failed: \(error.localizedDescription)", style: .error)
            )
            throw error
        }

        if diarizationEnabled {
            let segmentCount = transcriptionOutput.diarizedSegments?.count ?? 0
            if segmentCount > 0 {
                Log.app.info("Quick capture diarization produced \(segmentCount) segments")
            } else {
                Log.app.info("Quick capture diarization produced no attributed segments")
            }
        }

        let transcribedText = transcriptionOutput.text

        var (textAfterReplacements, appliedReplacements) = try dictionaryStore.applyReplacements(to: transcribedText)
        textAfterReplacements = normalizedTranscriptionText(textAfterReplacements)

        guard !isTranscriptionEffectivelyEmpty(textAfterReplacements) else {
            handleNoSpeechDetected(context: "quick-capture")
            return nil
        }
        self.lastAppliedReplacements = appliedReplacements

        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           settingsStore.currentAIProviderHasRequiredAPIKey() {
            do {
                let apiKey = settingsStore.configuredAPIKeyForCurrentAIProvider()
                let notePrompt = settingsStore.noteEnhancementPrompt
                let vocabularyWords = try dictionaryStore.fetchAllVocabularyWords().map(\.word)
                let replacementCorrections = appliedReplacements.map {
                    AIEnhancementService.ContextMetadata.ReplacementCorrection(
                        original: $0.original,
                        replacement: $0.replacement
                    )
                }
                let enhancementContext = AIEnhancementService.ContextMetadata(
                    hasClipboardText: false,
                    clipboardText: nil,
                    hasClipboardImage: false,
                    appContext: nil,
                    vocabularyWords: vocabularyWords,
                    replacementCorrections: replacementCorrections
                )

                let existingTags = (try? notesStore.getAllUniqueTags()) ?? []
                let enhancedNote = try await aiEnhancementService.enhanceNote(
                    content: textAfterReplacements,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    contentPrompt: notePrompt,
                    generateMetadata: true,
                    existingTags: existingTags,
                    context: enhancementContext,
                    provider: settingsStore.currentAIProvider
                )
                Log.app.info("Note enhancement completed: title='\(enhancedNote.title)', tags=\(enhancedNote.tags.count)")
                let normalizedEnhancedContent = normalizedTranscriptionText(enhancedNote.content)
                guard !isTranscriptionEffectivelyEmpty(normalizedEnhancedContent) else {
                    handleNoSpeechDetected(context: "quick-capture")
                    return nil
                }
                return AIEnhancementService.EnhancedNote(
                    content: normalizedEnhancedContent,
                    title: enhancedNote.title,
                    tags: enhancedNote.tags
                )
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
                handleRecordingStartFailure(error, source: source)
            }
        }
    }
    
    private func startRecording(source: RecordingTriggerSource) async throws {
        automaticDictionaryLearningService.cancelObservation()
        logRecordingStartAttempt(source: source)

        // If permissions were granted after launch, recreate global event taps
        // so escape-to-cancel and modifier tracking become available mid-session.
        ensureGlobalKeyMonitorsIfPossible()

        await beginStreamingSessionIfAvailable()

        let didStartRecording: Bool
        do {
            didStartRecording = try await audioRecorder.startRecording()
        } catch {
            if isStreamingTranscriptionSessionActive {
                await cancelStreamingSession(preserveInsertedText: true)
            }
            Log.app.error("Audio engine failed to start: \(error)")
            throw error
        }

        guard didStartRecording else {
            if isStreamingTranscriptionSessionActive {
                await cancelStreamingSession(preserveInsertedText: true)
            }
            Log.app.debug("Recording start already in progress; ignoring duplicate start request")
            return
        }

        if settingsStore.pauseMediaOnRecording || settingsStore.muteAudioDuringRecording {
            mediaPauseService.beginRecordingSession(
                pauseMedia: settingsStore.pauseMediaOnRecording,
                muteSystemAudio: settingsStore.muteAudioDuringRecording
            )
        }
        
        isRecording = true
        recordingStartTime = Date()
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil
        contextSessionState = nil
        lastFocusOrWindowUpdateAt = nil

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
                    Log.app.info("Captured UI context: hasAppName=\(!ctx.appName.isEmpty), hasWindowTitle=\(ctx.windowTitle != nil)")
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

        if shouldRunLiveContextSession() {
            startLiveContextSessionIfNeeded(initialSnapshot: capturedSnapshot)
        } else {
            updateVibeRuntimeStateFromSettings()
        }

        statusBarController.setRecordingState()

        startRecordingIndicatorSession()
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
            "recording_start_attempt id=\(self.recordingStartAttemptCounter) source=\(source.rawValue) resolved=\(String(describing: snapshot.resolvedStatus)) avaudio=\(snapshot.audioApplicationStatus) avcapture=\(snapshot.captureDeviceStatus) requestedThisLaunch=\(snapshot.hasRequestedThisLaunch) cachedDecision=\(cachedDecision) bundleId=\(bundleIdentifier) shortVersion=\(shortVersion) buildVersion=\(buildVersion) pid=\(ProcessInfo.processInfo.processIdentifier) onboardingCompleted=\(self.settingsStore.hasCompletedOnboarding) bundlePath=\(bundlePath) executablePath=\(executablePath)"
        )
    }

    private func normalizedTranscriptionText(_ text: String) -> String {
        Self.normalizedTranscriptionText(text)
    }

    static func normalizedTranscriptionText(_ text: String) -> String {
        TranscriptionPolicy.normalizedTranscriptionText(text)
    }
    private func isTranscriptionEffectivelyEmpty(_ text: String) -> Bool {
        Self.isTranscriptionEffectivelyEmpty(text)
    }

    static func isTranscriptionEffectivelyEmpty(_ text: String) -> Bool {
        TranscriptionPolicy.isTranscriptionEffectivelyEmpty(text)
    }

    static func shouldPersistHistory(outputSucceeded: Bool, text: String) -> Bool {
        TranscriptionPolicy.shouldPersistHistory(outputSucceeded: outputSucceeded, text: text)
    }

    static func shouldUseSpeakerDiarization(
        diarizationFeatureEnabled: Bool,
        isStreamingSessionActive: Bool
    ) -> Bool {
        TranscriptionPolicy.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: diarizationFeatureEnabled,
            isStreamingSessionActive: isStreamingSessionActive
        )
    }

    static func shouldUseStreamingTranscription(
        streamingFeatureEnabled: Bool,
        outputMode: OutputMode,
        aiEnhancementEnabled: Bool,
        isQuickCaptureMode: Bool
    ) -> Bool {
        TranscriptionPolicy.shouldUseStreamingTranscription(
            streamingFeatureEnabled: streamingFeatureEnabled,
            outputMode: outputMode,
            aiEnhancementEnabled: aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )
    }

    private func encodeDiarizationSegmentsJSON(_ segments: [DiarizedTranscriptSegment]?) -> String? {
        guard let segments, !segments.isEmpty else {
            return nil
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encodedData = try encoder.encode(segments)
            return String(data: encodedData, encoding: .utf8)
        } catch {
            Log.app.warning("Failed to encode diarization segments for history: \(error.localizedDescription)")
            return nil
        }
    }

    private func shouldUseStreamingTranscriptionForCurrentSession() -> Bool {
        Self.shouldUseStreamingTranscription(
            streamingFeatureEnabled: settingsStore.streamingFeatureEnabled,
            outputMode: outputManager.outputMode,
            aiEnhancementEnabled: settingsStore.aiEnhancementEnabled,
            isQuickCaptureMode: isQuickCaptureMode
        )
    }

    private func handleNoSpeechDetected(context: String) {
        Log.app.info("No speech detected for \(context); skipping output")
        toastService.show(
            ToastPayload(
                message: "No speech detected. Try speaking closer to your microphone."
            )
        )
    }

    private func handleRecordingStartFailure(_ error: Error, source: RecordingTriggerSource) {
        let isHotkeySource: Bool
        switch source {
        case .hotkeyToggle, .hotkeyPushToTalk, .hotkeyQuickCapturePTT, .hotkeyQuickCaptureToggle:
            isHotkeySource = true
        default:
            isHotkeySource = false
        }

        guard isHotkeySource,
              let audioError = error as? AudioRecorderError,
              case .permissionDenied = audioError else {
            return
        }

        AlertManager.shared.showMicrophonePermissionAlert()
    }

    private func beginStreamingSessionIfAvailable() async {
        let shouldUseStreaming = shouldUseStreamingTranscriptionForCurrentSession()
        guard shouldUseStreaming else {
            let reasons = [
                settingsStore.streamingFeatureEnabled ? nil : "feature-disabled",
                outputManager.outputMode == .directInsert ? nil : "output-mode-not-directInsert",
                settingsStore.aiEnhancementEnabled ? "ai-enhancement-enabled" : nil,
                isQuickCaptureMode ? "quick-capture-mode" : nil
            ].compactMap { $0 }
            Log.transcription.info("Streaming transcription disabled for session: \(reasons.joined(separator: ","))")
            isStreamingTranscriptionSessionActive = false
            clearStreamingSessionBindings(cancelPendingWork: true)
            return
        }

        do {
            setStreamingTranscriptionCallbacks()
            try await transcriptionService.prepareStreamingEngine()
            try await transcriptionService.startStreaming()
            outputManager.beginStreamingInsertion()
            attachStreamingAudioForwarding()
            isStreamingTranscriptionSessionActive = true
            Log.transcription.info("Streaming transcription enabled for current session")
        } catch {
            Log.transcription.error("Streaming transcription unavailable, falling back to batch: \(error)")
            await cancelStreamingSession(preserveInsertedText: true)
        }
    }

    private func setStreamingTranscriptionCallbacks() {
        transcriptionService.setStreamingCallbacks(
            onPartial: { [weak self] text in
                Task { @MainActor in
                    self?.enqueueStreamingInsertionUpdate(text, source: "partial")
                }
            },
            onFinalUtterance: { [weak self] text in
                Task { @MainActor in
                    self?.enqueueStreamingInsertionUpdate(text, source: "final-utterance")
                }
            }
        )
    }

    private func attachStreamingAudioForwarding() {
        audioRecorder.onAudioBuffer = { [weak self] buffer in
            self?.enqueueStreamingAudioBuffer(buffer)
        }
    }

    private func enqueueStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isStreamingTranscriptionSessionActive else { return }

        let previousTask = streamingAudioProcessingTask
        streamingAudioProcessingTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self, self.isStreamingTranscriptionSessionActive else { return }
            do {
                try await self.transcriptionService.processStreamingAudioBuffer(buffer)
            } catch {
                Log.transcription.error("Streaming audio buffer processing failed: \(error)")
            }
        }
    }

    private func enqueueStreamingInsertionUpdate(_ text: String, source: String) {
        guard isStreamingTranscriptionSessionActive else { return }

        let previousTask = streamingInsertionUpdateTask
        streamingInsertionUpdateTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self, self.isStreamingTranscriptionSessionActive else { return }
            do {
                try await self.outputManager.updateStreamingInsertion(with: text)
                Log.transcription.debug("Applied streaming \(source) update (chars=\(text.count))")
            } catch {
                Log.output.error("Failed applying streaming \(source) update: \(error)")
            }
        }
    }

    private func flushStreamingSessionWork() async {
        if let task = streamingAudioProcessingTask {
            _ = await task.result
        }
        streamingAudioProcessingTask = nil

        if let task = streamingInsertionUpdateTask {
            _ = await task.result
        }
        streamingInsertionUpdateTask = nil
    }

    private func clearStreamingSessionBindings(cancelPendingWork: Bool) {
        audioRecorder.onAudioBuffer = nil
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)
        if cancelPendingWork {
            streamingAudioProcessingTask?.cancel()
            streamingInsertionUpdateTask?.cancel()
            streamingAudioProcessingTask = nil
            streamingInsertionUpdateTask = nil
        }
    }

    private func cancelStreamingSession(preserveInsertedText: Bool) async {
        clearStreamingSessionBindings(cancelPendingWork: true)
        await transcriptionService.cancelStreaming()
        await outputManager.cancelStreamingInsertion(removeInsertedText: !preserveInsertedText)
        isStreamingTranscriptionSessionActive = false
    }

    private func stopRecordingAndFinalizeStreaming() async throws {
        guard let startTime = recordingStartTime else {
            Log.app.warning("stopRecordingAndFinalizeStreaming called but recordingStartTime is nil")
            return
        }

        isRecording = false
        mediaPauseService.endRecordingSession()
        suspendLiveContextSessionUpdates()
        isProcessing = true

        statusBarController.setProcessingState()

        transitionRecordingIndicatorToProcessing()

        defer {
            resetProcessingState()
        }

        do {
            _ = try await audioRecorder.stopRecording()
        } catch {
            Log.app.error("Failed to stop recording for streaming session: \(error)")
            await cancelStreamingSession(preserveInsertedText: true)
            throw error
        }

        await flushStreamingSessionWork()
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)

        let finalStreamedText: String
        do {
            finalStreamedText = try await transcriptionService.stopStreaming()
            Log.transcription.info("Streaming transcription finalized")
        } catch {
            Log.transcription.error("Failed to stop streaming transcription: \(error)")
            await cancelStreamingSession(preserveInsertedText: true)
            throw error
        }

        clearStreamingSessionBindings(cancelPendingWork: false)
        isStreamingTranscriptionSessionActive = false

        var (textAfterReplacements, appliedReplacements) = try dictionaryStore.applyReplacements(to: finalStreamedText)
        textAfterReplacements = normalizedTranscriptionText(textAfterReplacements)
        self.lastAppliedReplacements = appliedReplacements
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }

        guard !isTranscriptionEffectivelyEmpty(textAfterReplacements) else {
            handleNoSpeechDetected(context: "streaming recording")
            try? await outputManager.finishStreamingInsertion(finalText: "", appendTrailingSpace: false)
            return
        }

        var outputSucceeded = false
        do {
            try await outputManager.finishStreamingInsertion(
                finalText: textAfterReplacements,
                appendTrailingSpace: settingsStore.addTrailingSpace
            )
            outputSucceeded = true
            Log.transcription.debug("Applied final streaming transcription output")
        } catch {
            Log.output.error("Final streaming insertion failed: \(error)")
            await outputManager.cancelStreamingInsertion(removeInsertedText: false)
        }

        guard Self.shouldPersistHistory(outputSucceeded: outputSucceeded, text: textAfterReplacements) else {
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        do {
            try historyStore.save(
                text: textAfterReplacements,
                originalText: nil,
                duration: duration,
                modelUsed: settingsStore.selectedModel,
                enhancedWith: nil,
                diarizationSegmentsJSON: nil
            )
            updateRecentTranscriptsMenu()
        } catch {
            Log.app.error("Failed to save streamed transcription to history: \(error)")
        }
    }
    
    private func stopRecordingAndTranscribe() async throws {
        guard let startTime = recordingStartTime else {
            Log.app.warning("stopRecordingAndTranscribe called but recordingStartTime is nil")
            return
        }

        if isStreamingTranscriptionSessionActive {
            try await stopRecordingAndFinalizeStreaming()
            return
        }

        isRecording = false
        mediaPauseService.endRecordingSession()
        suspendLiveContextSessionUpdates()
        isProcessing = true
        var didResetProcessingState = false

        statusBarController.setProcessingState()
        
        transitionRecordingIndicatorToProcessing()
        
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
            handleNoSpeechDetected(context: "recording")
            return
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let diarizationEnabled = Self.shouldUseSpeakerDiarization(
            diarizationFeatureEnabled: settingsStore.diarizationFeatureEnabled,
            isStreamingSessionActive: false
        )
        Log.app.info("Speaker diarization \(diarizationEnabled ? "enabled" : "disabled") for batch transcription")

        let transcriptionOutput: TranscriptionOutput
        do {
            transcriptionOutput = try await transcriptionService.transcribe(
                audioData: audioData,
                diarizationEnabled: diarizationEnabled,
                options: TranscriptionOptions(language: settingsStore.selectedAppLanguage)
            )
        } catch let error as TranscriptionService.TranscriptionError {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            let message = if case .modelNotLoaded = error {
                "No model loaded. Please download a model in Settings."
            } else {
                "Transcription failed: \(error.localizedDescription)"
            }
            toastService.show(
                ToastPayload(message: message, style: .error)
            )
            throw error
        } catch {
            Log.app.error("Transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            toastService.show(
                ToastPayload(message: "Transcription failed: \(error.localizedDescription)", style: .error)
            )
            throw error
        }

        if diarizationEnabled {
            let segmentCount = transcriptionOutput.diarizedSegments?.count ?? 0
            if segmentCount > 0 {
                Log.app.info("Batch diarization produced \(segmentCount) segments")
            } else {
                Log.app.info("Batch diarization produced no attributed segments")
            }
        }

        let diarizationSegmentsJSON = encodeDiarizationSegmentsJSON(transcriptionOutput.diarizedSegments)
        let transcribedText = transcriptionOutput.text

        var (textAfterReplacements, appliedReplacements) = try dictionaryStore.applyReplacements(to: transcribedText)
        textAfterReplacements = normalizedTranscriptionText(textAfterReplacements)

        guard !isTranscriptionEffectivelyEmpty(textAfterReplacements) else {
            handleNoSpeechDetected(context: "recording")
            return
        }
        self.lastAppliedReplacements = appliedReplacements
        
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }
        
        // Mention rewrite: resolve spoken file mentions to app-specific syntax
        // Runs whenever adapter supports file mentions AND workspace roots are derivable
        // (not gated by isCodeEditorContext — enables Antigravity and other non-IDE adapters)
        var textAfterMentions = textAfterReplacements
        var mentionFormattingCapabilities = capturedAdapterCapabilities
        let derivedWorkspaceRoots = deriveWorkspaceRoots(
            routingSignal: capturedRoutingSignal,
            snapshot: capturedSnapshot
        )
        let shouldUsePlaceholderMentions = settingsStore.aiEnhancementEnabled &&
            settingsStore.apiEndpoint != nil &&
            settingsStore.currentAIProviderHasRequiredAPIKey()
        if let capabilities = capturedAdapterCapabilities,
           capabilities.supportsFileMentions {
            let resolvedMentionFormatting = settingsStore.resolveMentionFormatting(
                editorBundleIdentifier: capturedRoutingSignal?.appBundleIdentifier,
                terminalProviderIdentifier: capturedRoutingSignal?.terminalProviderIdentifier,
                adapterDefaultTemplate: capabilities.mentionTemplate,
                adapterDefaultPrefix: capabilities.mentionPrefix
            )
            let effectiveCapabilities = capabilities.withMentionFormatting(
                prefix: resolvedMentionFormatting.mentionPrefix,
                template: resolvedMentionFormatting.mentionTemplate
            )
            mentionFormattingCapabilities = effectiveCapabilities
            if !derivedWorkspaceRoots.isEmpty {
                let rewriteResult: MentionRewriteResult
                if shouldUsePlaceholderMentions {
                    rewriteResult = await mentionRewriteService.rewriteToCanonicalPlaceholders(
                        text: textAfterReplacements,
                        capabilities: effectiveCapabilities,
                        workspaceRoots: derivedWorkspaceRoots,
                        activeDocumentPath: capturedSnapshot?.appContext?.documentPath
                    )
                } else {
                    rewriteResult = await mentionRewriteService.rewrite(
                        text: textAfterReplacements,
                        capabilities: effectiveCapabilities,
                        workspaceRoots: derivedWorkspaceRoots,
                        activeDocumentPath: capturedSnapshot?.appContext?.documentPath
                    )
                }
                textAfterMentions = rewriteResult.text
                if rewriteResult.didRewrite {
                    Log.app.info("Mention rewrite: \(rewriteResult.rewrittenCount) mention(s) rewritten, \(rewriteResult.preservedCount) preserved")
                }
            } else {
                let adapterName = capturedAdapterCapabilities?.displayName ?? "unknown"
                let hasDocPath = capturedSnapshot?.appContext?.documentPath != nil
                let debugSummary = mentionRewriteWorkspaceDebugSummary(
                    adapterName: adapterName,
                    routingSignal: capturedRoutingSignal,
                    snapshot: capturedSnapshot,
                    derivedWorkspaceRoots: derivedWorkspaceRoots
                )
                Log.app.warning("Adapter '\(adapterName)' supports file mentions but no workspace roots derived (documentPath available: \(hasDocPath)); skipping mention rewrite. \(debugSummary)")
            }
        }
        
        var finalText = normalizedTranscriptionText(textAfterMentions)
        var originalText: String? = nil
        var enhancedWithModel: String? = nil

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           settingsStore.currentAIProviderHasRequiredAPIKey() {
            do {
                let apiKey = settingsStore.configuredAPIKeyForCurrentAIProvider()
                originalText = textAfterMentions
                Log.app.info("AI enhancement enabled, saving original text before enhancement")
                
                var basePrompt: String
                if let presetId = settingsStore.selectedPresetId,
                   let presetUUID = UUID(uuidString: presetId),
                   let allPresets = try? promptPresetStore.fetchAll(),
                   let selectedPreset = allPresets.first(where: { $0.id == presetUUID }) {
                    basePrompt = selectedPreset.prompt
                } else {
                    basePrompt = settingsStore.aiEnhancementPrompt
                }

                let vocabularyWords = try dictionaryStore.fetchAllVocabularyWords().map(\.word)
                let replacementCorrections = lastAppliedReplacements.map {
                    AIEnhancementService.ContextMetadata.ReplacementCorrection(
                        original: $0.original,
                        replacement: $0.replacement
                    )
                }

                if mentionFormattingCapabilities?.supportsFileMentions == true {
                    basePrompt += "\n\nIf the input contains file placeholders formatted as [[:relative/path.ext:]], preserve each placeholder token exactly. Do not change brackets, colons, slashes, file names, or extensions inside those tokens."
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

                let liveSessionContext = currentLiveSessionContext()
                
                if let context = capturedContext {
                    let hasClipboardText = context.clipboardText != nil && !context.clipboardText!.isEmpty
                    clipboardText = hasClipboardText ? context.clipboardText : nil
                    
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: hasClipboardText,
                        clipboardText: clipboardText,
                        hasClipboardImage: false,
                        appContext: capturedSnapshot?.appContext,
                        adapterCapabilities: mentionFormattingCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary,
                        liveSessionContext: liveSessionContext,
                        vocabularyWords: vocabularyWords,
                        replacementCorrections: replacementCorrections
                    )
                } else if let appContext = capturedSnapshot?.appContext {
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: false,
                        clipboardText: nil,
                        hasClipboardImage: false,
                        appContext: appContext,
                        adapterCapabilities: mentionFormattingCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary,
                        liveSessionContext: liveSessionContext,
                        vocabularyWords: vocabularyWords,
                        replacementCorrections: replacementCorrections
                    )
                } else if let liveSessionContext {
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: false,
                        clipboardText: nil,
                        hasClipboardImage: false,
                        appContext: nil,
                        adapterCapabilities: mentionFormattingCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary,
                        liveSessionContext: liveSessionContext,
                        vocabularyWords: vocabularyWords,
                        replacementCorrections: replacementCorrections
                    )
                } else if !vocabularyWords.isEmpty || !replacementCorrections.isEmpty {
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: false,
                        clipboardText: nil,
                        hasClipboardImage: false,
                        appContext: nil,
                        adapterCapabilities: mentionFormattingCapabilities,
                        routingSignal: capturedRoutingSignal,
                        workspaceFileTree: workspaceTreeSummary,
                        liveSessionContext: nil,
                        vocabularyWords: vocabularyWords,
                        replacementCorrections: replacementCorrections
                    )
                }

                finalText = try await aiEnhancementService.enhance(
                    text: textAfterMentions,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    customPrompt: basePrompt,
                    imageBase64: nil,
                    context: contextMetadata,
                    provider: settingsStore.currentAIProvider
                )
                if let capabilities = mentionFormattingCapabilities,
                   capabilities.supportsFileMentions,
                   !derivedWorkspaceRoots.isEmpty {
                    let renderedPlaceholders = mentionRewriteService.renderCanonicalPlaceholders(
                        in: finalText,
                        capabilities: capabilities
                    )
                    finalText = renderedPlaceholders.text

                    if renderedPlaceholders.didRewrite {
                        Log.app.info("Post-enhancement placeholder render: \(renderedPlaceholders.rewrittenCount) placeholder(s) rendered, \(renderedPlaceholders.preservedCount) preserved")
                    } else {
                        let postEnhancementRewriteResult = await mentionRewriteService.rewrite(
                            text: finalText,
                            capabilities: capabilities,
                            workspaceRoots: derivedWorkspaceRoots,
                            activeDocumentPath: capturedSnapshot?.appContext?.documentPath
                        )
                        finalText = postEnhancementRewriteResult.text
                        if postEnhancementRewriteResult.didRewrite {
                            Log.app.info("Post-enhancement mention rewrite: \(postEnhancementRewriteResult.rewrittenCount) mention(s) rewritten, \(postEnhancementRewriteResult.preservedCount) preserved")
                        }
                    }
                }
                capturedContext = nil
                capturedSnapshot = nil
                capturedAdapterCapabilities = nil
                capturedRoutingSignal = nil
                stopLiveContextSession()
                enhancedWithModel = settingsStore.aiModel
                Log.app.info("AI enhancement completed, original: \(textAfterMentions.count) chars, enhanced: \(finalText.count) chars")
            } catch {
                Log.app.error("AI enhancement failed: \(error)")
                toastService.show(
                    ToastPayload(
                        message: "AI enhancement failed. Transcription inserted without enhancement.",
                        style: .error
                    )
                )
                // Keep originalText so the unenhanced transcription is saved to history
            }
        } else {
            if !settingsStore.aiEnhancementEnabled {
                Log.app.debug("AI enhancement disabled, no original text to save")
            } else if settingsStore.apiEndpoint == nil {
                Log.app.debug("AI enhancement enabled but no API endpoint configured")
            } else if settingsStore.requiresAPIKey(for: settingsStore.currentAIProvider) {
                Log.app.debug("AI enhancement enabled but no API key configured")
            }
        }

        finalText = normalizedTranscriptionText(finalText)
        guard !isTranscriptionEffectivelyEmpty(finalText) else {
            handleNoSpeechDetected(context: "recording")
            return
        }

        let directInsertSnapshot = outputManager.outputMode == .directInsert
            && settingsStore.automaticDictionaryLearningEnabled
            ? contextEngineService.captureFocusedTextSnapshot()
            : nil
        var outputSucceeded = false
        do {
            if outputManager.outputMode == .directInsert {
                ensureAccessibilityPermissionForDirectInsert(trigger: "output", showFallbackAlert: true)
            }
            let outputText = settingsStore.addTrailingSpace ? finalText + " " : finalText
            try await outputManager.output(outputText)
            outputSucceeded = true
            if outputManager.outputMode == .directInsert,
               settingsStore.automaticDictionaryLearningEnabled {
                automaticDictionaryLearningService.beginObservation(
                    preInsertSnapshot: directInsertSnapshot,
                    insertedText: outputText
                )
            } else if outputManager.outputMode == .directInsert {
                Log.app.info("Automatic dictionary learning disabled in settings; skipping observation")
            }
        } catch {
            Log.app.error("Output failed: \(error)")
        }

        guard Self.shouldPersistHistory(outputSucceeded: outputSucceeded, text: finalText) else { return }

        do {
            try historyStore.save(
                text: finalText,
                originalText: originalText,
                duration: duration,
                modelUsed: settingsStore.selectedModel,
                enhancedWith: enhancedWithModel,
                diarizationSegmentsJSON: diarizationSegmentsJSON
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
            teardownEscapeKeyMonitor()
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
            resetEventTapRecoveryState(for: .escape)
            installEscapeGlobalMonitorFallbackIfNeeded()
            return
        }

        installEscapeGlobalMonitorFallbackIfNeeded()
        
        escapeEventTap = eventTap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            Log.app.error("Failed to create run loop source for escape CGEventTap")
            escapeEventTap = nil
            resetEventTapRecoveryState(for: .escape)
            return
        }

        escapeRunLoopSource = source
        eventTapRunLoopThread.performAndWait { runLoop in
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        resetEventTapRecoveryState(for: .escape)
        Log.app.info("Escape key monitor installed")
    }

    private func setupModifierKeyMonitor() {
        if modifierEventTap != nil, modifierRunLoopSource != nil {
            removeModifierGlobalMonitorFallbackIfNeeded()
            return
        }

        if modifierEventTap != nil, modifierRunLoopSource == nil {
            Log.hotkey.warning("Modifier event tap missing run loop source; recreating monitor")
            teardownModifierKeyMonitor()
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
            resetEventTapRecoveryState(for: .modifier)
            installModifierGlobalMonitorFallbackIfNeeded()
            return
        }

        removeModifierGlobalMonitorFallbackIfNeeded()

        modifierEventTap = eventTap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            Log.hotkey.error("Failed to create run loop source for modifier CGEventTap")
            modifierEventTap = nil
            resetEventTapRecoveryState(for: .modifier)
            return
        }

        modifierRunLoopSource = source
        eventTapRunLoopThread.performAndWait { runLoop in
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        resetEventTapRecoveryState(for: .modifier)
        Log.hotkey.info("Modifier key monitor installed")
    }

    private func teardownEscapeKeyMonitor() {
        escapeEventTapRecoveryTask?.cancel()
        escapeEventTapRecoveryTask = nil

        if let source = escapeRunLoopSource {
            let eventTap = escapeEventTap
            eventTapRunLoopThread.performAndWait { runLoop in
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: false)
                }
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
        } else if let eventTap = escapeEventTap {
            eventTapRunLoopThread.performAndWait { _ in
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
        }

        escapeEventTap = nil
        escapeRunLoopSource = nil
        resetEventTapRecoveryState(for: .escape)
    }

    private func teardownModifierKeyMonitor() {
        modifierEventTapRecoveryTask?.cancel()
        modifierEventTapRecoveryTask = nil

        if let source = modifierRunLoopSource {
            let eventTap = modifierEventTap
            eventTapRunLoopThread.performAndWait { runLoop in
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: false)
                }
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
        } else if let eventTap = modifierEventTap {
            eventTapRunLoopThread.performAndWait { _ in
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
        }

        modifierEventTap = nil
        modifierRunLoopSource = nil
        resetEventTapRecoveryState(for: .modifier)
    }

    private func scheduleEventTapRecovery(for kind: EventTapKind, disabledType: CGEventType) {
        let now = Date()

        switch kind {
        case .escape:
            let decision = Self.determineEventTapRecovery(
                now: now,
                lastDisableAt: escapeEventTapDisableState.lastDisableAt,
                consecutiveDisableCount: escapeEventTapDisableState.consecutiveDisableCount,
                disableLoopWindow: eventTapDisableLoopWindow,
                maxReenableAttemptsBeforeRecreate: maxEventTapReenableAttemptsBeforeRecreate
            )
            escapeEventTapDisableState.lastDisableAt = now
            escapeEventTapDisableState.consecutiveDisableCount = decision.consecutiveDisableCount
            escapeEventTapDisableState.lastDisabledTypeRawValue = disabledType.rawValue

            guard escapeEventTapRecoveryTask == nil else { return }
            let recoveryDelay = eventTapRecoveryDelay
            escapeEventTapRecoveryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: recoveryDelay)
                guard let self, !Task.isCancelled else { return }
                self.escapeEventTapRecoveryTask = nil
                self.performEventTapRecovery(for: .escape)
            }
        case .modifier:
            let decision = Self.determineEventTapRecovery(
                now: now,
                lastDisableAt: modifierEventTapDisableState.lastDisableAt,
                consecutiveDisableCount: modifierEventTapDisableState.consecutiveDisableCount,
                disableLoopWindow: eventTapDisableLoopWindow,
                maxReenableAttemptsBeforeRecreate: maxEventTapReenableAttemptsBeforeRecreate
            )
            modifierEventTapDisableState.lastDisableAt = now
            modifierEventTapDisableState.consecutiveDisableCount = decision.consecutiveDisableCount
            modifierEventTapDisableState.lastDisabledTypeRawValue = disabledType.rawValue

            guard modifierEventTapRecoveryTask == nil else { return }
            let recoveryDelay = eventTapRecoveryDelay
            modifierEventTapRecoveryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: recoveryDelay)
                guard let self, !Task.isCancelled else { return }
                self.modifierEventTapRecoveryTask = nil
                self.performEventTapRecovery(for: .modifier)
            }
        }
    }

    private func performEventTapRecovery(for kind: EventTapKind) {
        switch kind {
        case .escape:
            let state = escapeEventTapDisableState
            resetEventTapRecoveryState(for: .escape)

            guard state.consecutiveDisableCount > 0 else { return }

            if state.consecutiveDisableCount >= maxEventTapReenableAttemptsBeforeRecreate {
                Log.app.error(
                    "Escape key monitor kept disabling (count=\(state.consecutiveDisableCount), lastType=\(state.lastDisabledTypeRawValue ?? 0)); recreating monitor"
                )
                teardownEscapeKeyMonitor()
                setupEscapeKeyMonitor()
                return
            }

            guard let tap = escapeEventTap else { return }

            eventTapRunLoopThread.performAndWait { _ in
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.app.warning("Escape key monitor was disabled (type=\(state.lastDisabledTypeRawValue ?? 0)); re-enabled after backoff")
        case .modifier:
            let state = modifierEventTapDisableState
            resetEventTapRecoveryState(for: .modifier)

            guard state.consecutiveDisableCount > 0 else { return }

            if state.consecutiveDisableCount >= maxEventTapReenableAttemptsBeforeRecreate {
                Log.hotkey.error(
                    "Modifier key monitor kept disabling (count=\(state.consecutiveDisableCount), lastType=\(state.lastDisabledTypeRawValue ?? 0)); recreating monitor"
                )
                teardownModifierKeyMonitor()
                setupModifierKeyMonitor()
                return
            }

            guard let tap = modifierEventTap else { return }

            eventTapRunLoopThread.performAndWait { _ in
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.hotkey.warning("Modifier key monitor was disabled (type=\(state.lastDisabledTypeRawValue ?? 0)); re-enabled after backoff")
        }
    }

    private func resetEventTapRecoveryState(for kind: EventTapKind) {
        switch kind {
        case .escape:
            escapeEventTapDisableState = EventTapDisableState()
        case .modifier:
            modifierEventTapDisableState = EventTapDisableState()
        }
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
            Log.app.warning("Using NSEvent global monitor fallback for escape key (observation only; suppression unavailable)")
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
    
    static func shouldSuppressEscapeEvent(isRecording: Bool, isProcessing: Bool) -> Bool {
        RecordingInteractionPolicy.shouldSuppressEscapeEvent(
            isRecording: isRecording,
            isProcessing: isProcessing
        )
    }

    static func isDoubleEscapePress(
        now: Date,
        lastEscapeTime: Date?,
        threshold: TimeInterval
    ) -> Bool {
        RecordingInteractionPolicy.isDoubleEscapePress(
            now: now,
            lastEscapeTime: lastEscapeTime,
            threshold: threshold
        )
    }

    private nonisolated func handleKeyEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                self.scheduleEventTapRecovery(for: .escape, disabledType: type)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else {
            Task { @MainActor in
                self.scheduleFocusOrWindowContextRefreshIfNeeded()
            }
            return Unmanaged.passUnretained(event)
        }
        
        let shouldSuppress: Bool
        if Thread.isMainThread {
            shouldSuppress = MainActor.assumeIsolated {
                let suppress = Self.shouldSuppressEscapeEvent(
                    isRecording: self.isRecording,
                    isProcessing: self.isProcessing
                )
                self.handleEscapeSignal(source: "cg-event-tap")

                if suppress {
                    Log.app.info("Escape intercepted+suppressing (recordingOrProcessing=true)")
                } else {
                    Log.app.debug("Escape observed+forwarding (recordingOrProcessing=false)")
                }

                return suppress
            }
        } else {
            shouldSuppress = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let suppress = Self.shouldSuppressEscapeEvent(
                        isRecording: self.isRecording,
                        isProcessing: self.isProcessing
                    )
                    self.handleEscapeSignal(source: "cg-event-tap")

                    if suppress {
                        Log.app.info("Escape intercepted+suppressing (recordingOrProcessing=true)")
                    } else {
                        Log.app.debug("Escape observed+forwarding (recordingOrProcessing=false)")
                    }

                    return suppress
                }
            }
        }

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
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
            Task { @MainActor in
                self.scheduleEventTapRecovery(for: .modifier, disabledType: type)
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
        
        if Self.isDoubleEscapePress(
            now: now,
            lastEscapeTime: lastEscapeTime,
            threshold: doubleEscapeThreshold
        ) {
            lastEscapeTime = nil
            floatingIndicatorState.clearEscapePrimed()
            cancelCurrentOperation()
        } else {
            lastEscapeTime = now
            if settingsStore.floatingIndicatorEnabled {
                floatingIndicatorState.showEscapePrimed()
            }
        }
    }
    
    private func cancelCurrentOperation() {
        guard isRecording || isProcessing else {
            Log.app.debug("Double-escape pressed but no operation in progress")
            return
        }
        
        Log.app.info("Cancelling current operation via double-escape")
        let hadStreamingSession = isStreamingTranscriptionSessionActive
        clearStreamingSessionBindings(cancelPendingWork: true)
        isStreamingTranscriptionSessionActive = false
        mediaTranscriptionTask?.cancel()
        mediaTranscriptionTask = nil
        mediaTranscriptionState.showLibrary()
        mediaTranscriptionState.setLibraryMessage("Transcription canceled.")
        mediaTranscriptionState.clearCurrentJob()
        if hadStreamingSession {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.transcriptionService.cancelStreaming()
                await self.outputManager.cancelStreamingInsertion(removeInsertedText: false)
            }
        }

        audioRecorder.resetAudioEngine()
        mediaPauseService.endRecordingSession()
        isRecording = false
        isProcessing = false
        recordingStartTime = nil
        capturedContext = nil
        capturedSnapshot = nil
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil
        stopLiveContextSession()
        updateVibeRuntimeStateFromSettings()
        error = nil

        statusBarController.setIdleState()
        statusBarController.updateMenuState()
        
        finishIndicatorSession()
    }

    private func resetProcessingState() {
        mediaPauseService.endRecordingSession()
        isProcessing = false
        recordingStartTime = nil
        capturedContext = nil
        capturedSnapshot = nil
        capturedAdapterCapabilities = nil
        capturedRoutingSignal = nil
        stopLiveContextSession()
        updateVibeRuntimeStateFromSettings()
        statusBarController.setIdleState()
        statusBarController.updateMenuState()

        finishIndicatorSession()
    }

    // MARK: - Floating Indicator Actions

    private func handleHideFloatingIndicatorForOneHour() {
        let hideDuration: TimeInterval = 60 * 60
        floatingIndicatorHiddenUntil = Date().addingTimeInterval(hideDuration)

        hideAllFloatingIndicators()

        floatingIndicatorHiddenTask?.cancel()
        floatingIndicatorHiddenTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(hideDuration * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run {
                guard let self = self else { return }
                self.floatingIndicatorHiddenUntil = nil
                self.updateFloatingIndicatorVisibility()
            }
        }

        Log.ui.info("Floating indicator hidden for one hour")
    }

    private func handleReportIssue() {
        guard let supportURL = URL(string: "https://github.com/watzon/pindrop/issues") else { return }
        NSWorkspace.shared.open(supportURL)
    }

    private func handleSelectInputDeviceUID(_ uid: String) {
        settingsStore.selectedInputDeviceUID = uid
        audioRecorder.setPreferredInputDeviceUID(uid)

        if uid.isEmpty {
            Log.audio.info("Selected input device: system default")
        } else {
            Log.audio.info("Selected input device UID: \(uid)")
        }
    }

    private func handleSelectLanguage(_ language: AppLanguage) {
        settingsStore.selectedAppLanguage = language
        Log.ui.info("Selected app language: \(language.rawValue)")
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

    private func handlePasteLastTranscript() async {
        do {
            let records = try historyStore.fetch(limit: 1)
            guard let lastRecord = records.first else {
                Log.app.warning("No transcripts to paste")
                return
            }

            if permissionManager.checkAccessibilityPermission() {
                do {
                    try await outputManager.pasteText(lastRecord.text)
                    Log.output.info("Pasted last transcript into active app")
                    return
                } catch {
                    Log.output.error("Failed to paste last transcript directly: \(error)")
                }
            }

            try outputManager.copyToClipboard(lastRecord.text)
            Log.output.info("Copied last transcript to clipboard (paste fallback)")
        } catch {
            Log.output.error("Failed to prepare last transcript for paste: \(error)")
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

    // MARK: - Media Transcription

    private func handleImportMediaFiles(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }
        startMediaTranscriptionTask(from: .file(firstURL))
    }

    private func handleSubmitMediaLink(_ link: String) {
        startMediaTranscriptionTask(from: .link(link))
    }

    private func handleDownloadDiarizationModel() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.modelManager.downloadFeatureModel(.diarization)
                self.mediaTranscriptionState.clearSetupIssue()
                self.mediaTranscriptionState.setLibraryMessage("Speaker diarization is ready.")
            } catch {
                self.mediaTranscriptionState.setSetupIssue(error.localizedDescription)
            }
        }
    }

    private func startMediaTranscriptionTask(from request: MediaTranscriptionRequest) {
        guard mediaTranscriptionTask == nil else {
            mediaTranscriptionState.setLibraryMessage("Another transcription is already in progress.")
            return
        }

        mediaTranscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performMediaTranscription(request)
            self.mediaTranscriptionTask = nil
        }
    }

    private func performMediaTranscription(_ request: MediaTranscriptionRequest) async {
        guard !isRecording && !isProcessing else {
            mediaTranscriptionState.setLibraryMessage("Finish the active transcription before starting another one.")
            return
        }

        await modelManager.refreshDownloadedFeatureModels()
        guard modelManager.isFeatureModelDownloaded(.diarization) else {
            mediaTranscriptionState.setSetupIssue("Download the speaker diarization model before starting media transcription.")
            return
        }

        let job = MediaTranscriptionJobState(
            request: request,
            destinationFolderID: mediaTranscriptionState.selectedFolderID,
            stage: request.sourceKind == .webLink ? .preflight : .importing,
            progress: nil,
            detail: request.sourceKind == .webLink ? "Checking yt-dlp and ffmpeg" : "Importing local media"
        )

        mediaTranscriptionState.beginJob(job)
        mainWindowController.showTranscribe()

        isProcessing = true
        statusBarController.setProcessingState()
        statusBarController.updateMenuState()
        startProcessingIndicatorSession()

        var didResetProcessingState = false

        defer {
            if !didResetProcessingState {
                resetProcessingState()
            }
        }

        do {
            let managedAsset = try await mediaIngestionService.ingest(
                request: request,
                jobID: job.id,
                progressHandler: { [weak self] progress, detail in
                    guard let self else { return }
                    let stage: MediaTranscriptionStage = request.sourceKind == .webLink ? .downloading : .importing
                    self.mediaTranscriptionState.updateJob(
                        stage: stage,
                        progress: progress,
                        detail: detail,
                        errorMessage: nil
                    )
                }
            )

            try Task.checkCancellation()

            mediaTranscriptionState.updateJob(
                stage: .preparingAudio,
                progress: nil,
                detail: "Preparing audio for transcription",
                errorMessage: nil
            )
            let preparedAudio = try await mediaPreparationService.prepareAudio(from: managedAsset.mediaURL)

            try Task.checkCancellation()

            mediaTranscriptionState.updateJob(
                stage: .transcribing,
                progress: nil,
                detail: "Running diarization and transcription",
                errorMessage: nil
            )

            let transcriptionOutput = try await transcriptionService.transcribe(
                audioData: preparedAudio.audioData,
                diarizationEnabled: true,
                options: TranscriptionOptions(language: settingsStore.selectedAppLanguage)
            )
            let diarizationSegmentsJSON = encodeDiarizationSegmentsJSON(transcriptionOutput.diarizedSegments)

            try Task.checkCancellation()

            mediaTranscriptionState.updateJob(
                stage: .saving,
                progress: nil,
                detail: "Saving transcript to history",
                errorMessage: nil
            )

            let finalText = normalizedTranscriptionText(transcriptionOutput.text)
            guard !isTranscriptionEffectivelyEmpty(finalText) else {
                throw MediaPreparationError.readFailed("No speech could be transcribed from this media.")
            }

            let record = try historyStore.save(
                text: finalText,
                originalText: nil,
                duration: preparedAudio.duration,
                modelUsed: settingsStore.selectedModel,
                enhancedWith: nil,
                diarizationSegmentsJSON: diarizationSegmentsJSON,
                sourceKind: managedAsset.sourceKind,
                sourceDisplayName: managedAsset.displayName,
                originalSourceURL: managedAsset.originalSourceURL,
                managedMediaPath: managedAsset.mediaURL.path,
                thumbnailPath: managedAsset.thumbnailURL?.path,
                folderID: job.destinationFolderID
            )
            updateRecentTranscriptsMenu()

            let shouldNavigateToDetail = mediaTranscriptionState.route == .processing(job.id)
            resetProcessingState()
            didResetProcessingState = true
            mediaTranscriptionState.completeCurrentJob(with: record.id, shouldNavigateToDetail: shouldNavigateToDetail)
        } catch is CancellationError {
            resetProcessingState()
            didResetProcessingState = true
            mediaTranscriptionState.showLibrary()
            mediaTranscriptionState.setLibraryMessage("Transcription canceled.")
            mediaTranscriptionState.clearCurrentJob()
        } catch let error as MediaIngestionError {
            Log.app.error("Media ingestion failed: \(error.localizedDescription)")
            resetProcessingState()
            didResetProcessingState = true
            mediaTranscriptionState.clearCurrentJob()
            if case .toolingUnavailable(let message) = error {
                mediaTranscriptionState.setSetupIssue(message)
            } else {
                mediaTranscriptionState.setLibraryMessage(error.localizedDescription)
            }
        } catch {
            Log.app.error("Media transcription failed: \(error)")
            resetProcessingState()
            didResetProcessingState = true
            let shouldReturnToLibrary = mediaTranscriptionState.route != .processing(job.id)
            mediaTranscriptionState.failCurrentJob(error.localizedDescription, returnToLibrary: shouldReturnToLibrary)
        }
    }

    // MARK: - Clear Audio Buffer

    private func handleClearAudioBuffer() async {
        guard isRecording else {
            finishIndicatorSession()
            return
        }

        Log.app.info("Clearing audio buffer")
        audioRecorder.cancelRecording()
        if isStreamingTranscriptionSessionActive {
            await cancelStreamingSession(preserveInsertedText: true)
        } else {
            clearStreamingSessionBindings(cancelPendingWork: true)
        }
        mediaPauseService.endRecordingSession()
        isRecording = false
        recordingStartTime = nil
        stopLiveContextSession()
        updateVibeRuntimeStateFromSettings()

        statusBarController.setIdleState()

        finishIndicatorSession()
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

        if !settingsStore.aiEnhancementEnabled {
            stopLiveContextSession()
        } else if isRecording, shouldRunLiveContextSession() {
            startLiveContextSessionIfNeeded(initialSnapshot: capturedSnapshot)
        }

        updateVibeRuntimeStateFromSettings()
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

        if settingsStore.floatingIndicatorEnabled {
            clearFloatingIndicatorTemporaryHiddenState()
        }

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
            try await loadAndActivateModel(named: modelName, provider: model.provider)
            settingsStore.selectedModel = modelName
            statusBarController.updateDynamicItems()
            Log.model.info("Switched to model \(modelName) successfully")
        } catch {
            if model.provider == .whisperKit {
                do {
                    try await attemptWhisperModelRepairAndReload(
                        modelName: modelName,
                        displayName: model.displayName
                    )
                    settingsStore.selectedModel = modelName
                    statusBarController.updateDynamicItems()
                    Log.model.info("Model repaired and switched successfully: \(modelName)")
                    return
                } catch {
                    handleModelLoadError(error, context: "Failed to repair switched model")
                    AlertManager.shared.showModelLoadErrorAlert(error: error)
                    return
                }
            }

            handleModelLoadError(error, context: "Failed to switch model")
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
        floatingIndicatorHiddenTask?.cancel()
        floatingIndicatorHiddenTask = nil
        teardownEscapeKeyMonitor()
        teardownModifierKeyMonitor()
        removeEscapeGlobalMonitorFallbackIfNeeded()
        removeModifierGlobalMonitorFallbackIfNeeded()
        eventTapRunLoopThread.stopIfNeeded()
    }
}
