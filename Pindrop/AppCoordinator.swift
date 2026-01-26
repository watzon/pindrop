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
    let outputManager: OutputManager
    let historyStore: HistoryStore
    let settingsStore: SettingsStore
    
    // MARK: - UI Controllers
    
    let statusBarController: StatusBarController
    let floatingIndicatorController: FloatingIndicatorController
    let onboardingController: OnboardingWindowController
    let splashController: SplashWindowController
    let mainWindowController: MainWindowController
    
    // MARK: - State
    
    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var error: Error?
    
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Escape Key Cancellation
    
    private var escapeMonitor: Any?
    private var lastEscapeTime: Date?
    private let doubleEscapeThreshold: TimeInterval = 0.4
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.permissionManager = PermissionManager()
        self.audioRecorder = AudioRecorder(permissionManager: permissionManager)
        self.transcriptionService = TranscriptionService()
        self.modelManager = ModelManager()
        self.aiEnhancementService = AIEnhancementService()
        self.hotkeyManager = HotkeyManager()
        self.settingsStore = SettingsStore()
        
        let initialOutputMode: OutputMode = settingsStore.outputMode == "directInsert" ? .directInsert : .clipboard
        self.outputManager = OutputManager(outputMode: initialOutputMode)
        self.historyStore = HistoryStore(modelContext: modelContext)
        
        self.statusBarController = StatusBarController(
            audioRecorder: audioRecorder,
            settingsStore: settingsStore
        )
        self.statusBarController.setModelContainer(modelContainer)
        self.floatingIndicatorController = FloatingIndicatorController()
        self.onboardingController = OnboardingWindowController()
        self.splashController = SplashWindowController()
        self.mainWindowController = MainWindowController()
        self.mainWindowController.setModelContainer(modelContainer)
        self.mainWindowController.onOpenSettings = { [weak self] in
            self?.statusBarController.showSettings(tab: .hotkeys)
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

        self.statusBarController.onToggleFloatingIndicator = { [weak self] in
            self?.handleToggleFloatingIndicator()
        }

        self.statusBarController.onOpenHistory = { [weak self] in
            self?.handleOpenHistory()
        }

        self.statusBarController.onSelectModel = { [weak self] modelName in
            self?.handleSelectModel(modelName)
        }

        self.statusBarController.setMainWindowController(mainWindowController)
        
        self.audioRecorder.onAudioLevel = { [weak self] level in
            self?.floatingIndicatorController.updateAudioLevel(level)
        }
        
        self.floatingIndicatorController.onStopRecording = { [weak self] in
            Task { @MainActor in
                await self?.handleToggleRecording()
            }
        }
        
        setupHotkeys()
        observeSettings()
        setupEscapeKeyMonitor()
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
            return
        }
        
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
        if outputManager.outputMode == .directInsert && !outputManager.checkAccessibilityPermission() {
            _ = outputManager.requestAccessibilityPermission()
        }
    }
    
    private func startNormalOperation() async {
        let micGranted = await permissionManager.requestPermission()
        if !micGranted {
            Log.app.warning("Microphone permission denied - recording will not work")
            AlertManager.shared.showMicrophonePermissionAlert()
        }

        if outputManager.outputMode == .directInsert && !outputManager.checkAccessibilityPermission() {
            _ = outputManager.requestAccessibilityPermission()
        }

        do {
            let modelName = settingsStore.selectedModel
            try await transcriptionService.loadModel(modelName: modelName)
        } catch {
            self.error = error
            Log.app.error("Failed to load transcription model: \(error)")
        }

        // Load recent transcripts for the menu
        updateRecentTranscriptsMenu()
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
                    
                    self.registerHotkeysFromSettings()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Recording Flow
    
    private func handlePushToTalkStart() async {
        guard !isRecording && !isProcessing else { return }
        
        do {
            try await startRecording()
        } catch {
            self.error = error
            Log.app.error("Failed to start recording: \(error)")
        }
    }
    
    private func handlePushToTalkEnd() async {
        guard isRecording else { return }
        
        do {
            try await stopRecordingAndTranscribe()
        } catch {
            self.error = error
            Log.app.error("Failed to stop recording: \(error)")
        }
    }
    
    private func handleToggleRecording() async {
        if isRecording {
            do {
                try await stopRecordingAndTranscribe()
            } catch {
                self.error = error
                Log.app.error("Failed to stop recording: \(error)")
            }
        } else if !isProcessing {
            do {
                try await startRecording()
            } catch {
                self.error = error
                Log.app.error("Failed to start recording: \(error)")
            }
        }
    }
    
    private func startRecording() async throws {
        isRecording = true
        recordingStartTime = Date()
        
        statusBarController.setRecordingState()
        
        if settingsStore.floatingIndicatorEnabled {
            floatingIndicatorController.startRecording()
        }
        
        try await audioRecorder.startRecording()
    }
    
    private func stopRecordingAndTranscribe() async throws {
        guard let startTime = recordingStartTime else {
            Log.app.warning("stopRecordingAndTranscribe called but recordingStartTime is nil")
            return
        }
        
        isRecording = false
        isProcessing = true
        
        statusBarController.setProcessingState()
        
        if settingsStore.floatingIndicatorEnabled {
            floatingIndicatorController.stopRecording()
        }
        
        defer {
            isProcessing = false
            recordingStartTime = nil
            statusBarController.setIdleState()
            statusBarController.updateMenuState()
            
            if settingsStore.floatingIndicatorEnabled {
                floatingIndicatorController.finishProcessing()
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
            if case .modelNotLoaded = error {
                AlertManager.shared.showModelNotLoadedAlert()
            } else {
                AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            }
            throw error
        } catch {
            Log.app.error("Transcription failed: \(error)")
            AlertManager.shared.showTranscriptionErrorAlert(message: error.localizedDescription)
            throw error
        }
        
        var finalText = transcribedText
        var originalText: String? = nil
        var enhancedWithModel: String? = nil

        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           let apiKey = settingsStore.apiKey {
            do {
                originalText = transcribedText
                Log.app.info("AI enhancement enabled, saving original text before enhancement")
                finalText = try await aiEnhancementService.enhance(
                    text: transcribedText,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey,
                    model: settingsStore.aiModel,
                    customPrompt: settingsStore.aiEnhancementPrompt
                )
                enhancedWithModel = settingsStore.aiModel
                Log.app.info("AI enhancement completed, original: \(transcribedText.count) chars, enhanced: \(finalText.count) chars")
            } catch {
                Log.app.warning("AI enhancement failed, using original: \(error)")
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
            try await outputManager.output(finalText)
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
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            
            Task { @MainActor in
                self?.handleEscapeKeyPress()
            }
        }
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
        
        if isRecording {
            audioRecorder.cancelRecording()
            isRecording = false
        }
        
        isProcessing = false
        recordingStartTime = nil
        error = nil
        
        statusBarController.setIdleState()
        statusBarController.updateMenuState()
        
        if settingsStore.floatingIndicatorEnabled {
            floatingIndicatorController.finishProcessing()
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
            floatingIndicatorController.stopRecording()
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

    // MARK: - Toggle Floating Indicator

    private func handleToggleFloatingIndicator() {
        settingsStore.floatingIndicatorEnabled.toggle()
        let status = settingsStore.floatingIndicatorEnabled ? "enabled" : "disabled"
        Log.app.info("Floating indicator \(status)")
    }

    // MARK: - Open History

    private func handleOpenHistory() {
        mainWindowController.showHistory()
    }

    // MARK: - Select Model

    private func handleSelectModel(_ modelName: String) {
        settingsStore.selectedModel = modelName
        Log.app.info("Model changed to: \(modelName)")

        Task {
            do {
                try await transcriptionService.loadModel(modelName: modelName)
            } catch {
                Log.app.error("Failed to load model \(modelName): \(error)")
            }
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
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
