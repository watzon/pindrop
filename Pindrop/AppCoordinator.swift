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
            self?.statusBarController.showSettings()
        }
        
        self.statusBarController.onToggleRecording = { [weak self] in
            await self?.handleToggleRecording()
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
        if settingsStore.aiEnhancementEnabled,
           let apiEndpoint = settingsStore.apiEndpoint,
           let apiKey = settingsStore.apiKey {
            do {
                finalText = try await aiEnhancementService.enhance(
                    text: transcribedText,
                    apiEndpoint: apiEndpoint,
                    apiKey: apiKey
                )
            } catch {
                Log.app.warning("AI enhancement failed, using original: \(error)")
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
                duration: duration,
                modelUsed: settingsStore.selectedModel
            )
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
    
    func cleanup() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
