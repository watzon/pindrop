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

@MainActor
@Observable
final class AppCoordinator {
    
    // MARK: - Services
    
    let permissionManager: PermissionManager
    let audioRecorder: AudioRecorder
    let transcriptionService: TranscriptionService
    let modelManager: ModelManager
    let aiEnhancementService: AIEnhancementService
    let hotkeyManager: HotkeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    let outputManager: OutputManager
    let historyStore: HistoryStore
    let dictionaryStore: DictionaryStore
    let settingsStore: SettingsStore
    let notesStore: NotesStore
    let contextCaptureService: ContextCaptureService
    let promptPresetStore: PromptPresetStore

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

    // MARK: - Dictionary Replacements
    
    /// Stores the last applied dictionary replacements for use in AI enhancement prompts
    var lastAppliedReplacements: [(original: String, replacement: String)] = []
    
    // MARK: - Escape Key Cancellation
    
    private var escapeEventTap: CFMachPort?
    private var escapeRunLoopSource: CFRunLoopSource?
    private var modifierEventTap: CFMachPort?
    private var modifierRunLoopSource: CFRunLoopSource?
    private var lastEscapeTime: Date?
    private let doubleEscapeThreshold: TimeInterval = 0.4
    
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
        self.settingsStore = SettingsStore()
        self.audioRecorder.setPreferredInputDeviceUID(settingsStore.selectedInputDeviceUID)
        
        let initialOutputMode: OutputMode = settingsStore.outputMode == "directInsert" ? .directInsert : .clipboard
        self.outputManager = OutputManager(outputMode: initialOutputMode)
        self.historyStore = HistoryStore(modelContext: modelContext)
        self.dictionaryStore = DictionaryStore(modelContext: modelContext)
        self.notesStore = NotesStore(modelContext: modelContext, aiEnhancementService: aiEnhancementService, settingsStore: settingsStore)
        self.contextCaptureService = ContextCaptureService()
        self.promptPresetStore = PromptPresetStore(modelContext: modelContext)

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
            await self?.handleToggleRecording()
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

        self.statusBarController.setMainWindowController(mainWindowController)
        
        self.audioRecorder.onAudioLevel = { [weak self] level in
            self?.floatingIndicatorController.updateAudioLevel(level)
            self?.pillFloatingIndicatorController.updateAudioLevel(level)
        }
        
        self.floatingIndicatorController.onStopRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording()
            }
        }
        
        self.pillFloatingIndicatorController.onStopRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording()
            }
        }

        self.pillFloatingIndicatorController.onCancelRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleClearAudioBuffer()
            }
        }

        self.pillFloatingIndicatorController.onStartRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording()
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
        
        if outputManager.outputMode == .directInsert && !outputManager.checkAccessibilityPermission() {
            Log.app.info("Accessibility permission not granted after onboarding - direct insert will use clipboard fallback")
        }
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
        if micStatus == .notDetermined {
            let micGranted = await permissionManager.requestPermission()
            if !micGranted {
                Log.app.warning("Microphone permission denied - recording will not work")
                AlertManager.shared.showMicrophonePermissionAlert()
            }
        } else if micStatus == .denied || micStatus == .restricted {
            Log.app.warning("Microphone permission denied - recording will not work")
            AlertManager.shared.showMicrophonePermissionAlert()
        }

        if outputManager.outputMode == .directInsert && !outputManager.checkAccessibilityPermission() {
            Log.app.info("Accessibility permission not granted - direct insert will use clipboard fallback")
        }

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
        
        if !settingsStore.pushToTalkHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.pushToTalkHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.pushToTalkHotkeyModifiers))
            
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
        
        if !settingsStore.toggleHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.toggleHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.toggleHotkeyModifiers))
            
            _ = hotkeyManager.registerHotkey(
                keyCode: keyCode,
                modifiers: modifiers,
                identifier: "toggle-recording",
                mode: .toggle,
                onKeyDown: { [weak self] in
                    Task { @MainActor in
                        await self?.handleToggleRecording()
                    }
                },
                onKeyUp: nil
            )
        }

        if !settingsStore.copyLastTranscriptHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.copyLastTranscriptHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.copyLastTranscriptHotkeyModifiers))

            Log.hotkey.info("Registering copy-last-transcript: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.copyLastTranscriptHotkey)")

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

        if !settingsStore.quickCapturePTTHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.quickCapturePTTHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.quickCapturePTTHotkeyModifiers))

            Log.hotkey.info("Registering quick-capture-ptt: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCapturePTTHotkey)")

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

        if !settingsStore.quickCaptureToggleHotkey.isEmpty {
            let keyCode = UInt32(settingsStore.quickCaptureToggleHotkeyCode)
            let modifiers = HotkeyManager.ModifierFlags(rawValue: UInt32(settingsStore.quickCaptureToggleHotkeyModifiers))

            Log.hotkey.info("Registering quick-capture-toggle: keyCode=\(keyCode), modifiers=0x\(String(modifiers.rawValue, radix: 16)), string=\(self.settingsStore.quickCaptureToggleHotkey)")

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
    
    // MARK: - Settings Observation
    
    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }

                    let mode: OutputMode = self.settingsStore.outputMode == "clipboard" ? .clipboard : .directInsert
                    self.outputManager.setOutputMode(mode)

                    if mode == .directInsert {
                        let hasPermission = self.outputManager.checkAccessibilityPermission()
                        Log.app.info("Direct Insert mode selected, accessibility permission: \(hasPermission)")
                        if !hasPermission {
                            AlertManager.shared.showAccessibilityPermissionAlert()
                        }
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
            try await startRecording()
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
            try await startRecording()
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
                try await startRecording()
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

    private func handleToggleRecording() async {
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
                try await startRecording()
            } catch {
                self.error = error
                audioRecorder.resetAudioEngine()
                Log.app.error("Failed to start recording: \(error)")
            }
        }
    }
    
    private func startRecording() async throws {
        do {
            try await audioRecorder.startRecording()
        } catch {
            Log.app.error("Audio engine failed to start: \(error)")
            throw error
        }
        
        isRecording = true
        recordingStartTime = Date()

        if settingsStore.enableClipboardContext || settingsStore.enableImageContext || settingsStore.enableScreenshotContext {
            let clipboardText = settingsStore.enableClipboardContext ? contextCaptureService.captureClipboardText() : nil
            let clipboardImage = settingsStore.enableImageContext ? contextCaptureService.captureClipboardImage() : nil
            var screenshot: NSImage? = nil
            if settingsStore.enableScreenshotContext {
                let mode: ScreenshotMode
                switch settingsStore.screenshotMode {
                case "fullScreen":
                    mode = .fullScreen
                case "activeWindow":
                    mode = .activeWindow
                default:
                    mode = .activeWindow
                }
                screenshot = contextCaptureService.captureScreenshot(mode: mode)
            }
            capturedContext = CapturedContext(clipboardText: clipboardText, clipboardImage: clipboardImage, screenshot: screenshot)
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
        
        var finalText = textAfterReplacements
        var originalText: String? = nil
        var enhancedWithModel: String? = nil

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           let apiKey = settingsStore.apiKey {
            do {
                originalText = textAfterReplacements
                Log.app.info("AI enhancement enabled, saving original text before enhancement")
                
                // Build enhanced prompt with dictionary context
                // Get prompt from selected preset or use default
                var enhancedPrompt: String
                if let presetId = settingsStore.selectedPresetId,
                   let presetUUID = UUID(uuidString: presetId),
                   let allPresets = try? promptPresetStore.fetchAll(),
                   let selectedPreset = allPresets.first(where: { $0.id == presetUUID }) {
                    enhancedPrompt = selectedPreset.prompt.replacingOccurrences(of: "${transcription}", with: textAfterReplacements)
                } else {
                    enhancedPrompt = settingsStore.aiEnhancementPrompt ?? AIEnhancementService.defaultSystemPrompt
                }
                
                // Add vocabulary section if exists
                let vocabularyWords = try dictionaryStore.fetchAllVocabularyWords()
                if !vocabularyWords.isEmpty {
                    let wordList = vocabularyWords.map { $0.word }.joined(separator: ", ")
                    enhancedPrompt += "\n\nUser's vocabulary includes: \(wordList)"
                }
                
                // Add replacements section if applied
                if !lastAppliedReplacements.isEmpty {
                    let replacementList = lastAppliedReplacements
                        .map { "'\($0.original)' → '\($0.replacement)'" }
                        .joined(separator: ", ")
                    enhancedPrompt += "\n\nNote: These automatic replacements were applied to the transcription: \(replacementList). Please preserve these corrections."
                }
                
                var imageBase64: String? = nil
                var contextMetadata = AIEnhancementService.ContextMetadata.none
                var userMessageText = textAfterReplacements
                
                if let context = capturedContext {
                    let hasClipboardImage = context.clipboardImage != nil
                    let hasScreenshot = context.screenshot != nil
                    let hasClipboardText = context.clipboardText != nil && !context.clipboardText!.isEmpty
                    
                    contextMetadata = AIEnhancementService.ContextMetadata(
                        hasClipboardText: hasClipboardText,
                        hasClipboardImage: hasClipboardImage,
                        hasScreenshot: hasScreenshot
                    )
                    
                    let contextImage = context.clipboardImage ?? context.screenshot
                    if let image = contextImage,
                       ModelCapabilities.supportsVision(modelId: settingsStore.aiModel) {
                        imageBase64 = ImageResizer.toBase64PNG(image)
                    }
                    
                    if let clipboardText = context.clipboardText, !clipboardText.isEmpty {
                        userMessageText = """
                        <clipboard_text>
                        \(clipboardText)
                        </clipboard_text>
                        
                        <transcription>
                        \(textAfterReplacements)
                        </transcription>
                        """
                    }
                }
                
                finalText = try await aiEnhancementService.enhance(
                    text: userMessageText,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    customPrompt: enhancedPrompt,
                    imageBase64: imageBase64,
                    context: contextMetadata
                )
                capturedContext = nil
                enhancedWithModel = settingsStore.aiModel
                Log.app.info("AI enhancement completed, original: \(textAfterReplacements.count) chars, enhanced: \(finalText.count) chars")
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
            Log.app.error("Failed to create CGEventTap - Accessibility permission may be required")
            return
        }
        
        escapeEventTap = eventTap
        escapeRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        
        if let source = escapeRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func setupModifierKeyMonitor() {
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
            Log.hotkey.error("Failed to create modifier CGEventTap - Accessibility permission may be required")
            return
        }

        modifierEventTap = eventTap
        modifierRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let source = modifierRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    private nonisolated func handleKeyEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else { return Unmanaged.passUnretained(event) }
        
        Task { @MainActor in
            self.handleEscapeKeyPress()
        }
        
        return Unmanaged.passUnretained(event)
    }

    private nonisolated func handleModifierKeyEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
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
