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
    
    // MARK: - State
    
    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var error: Error?
    
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
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
        
        self.statusBarController.onToggleRecording = { [weak self] in
            await self?.handleToggleRecording()
        }
        
        setupHotkeys()
        observeSettings()
    }
    
    // MARK: - Lifecycle
    
    func start() async {
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
        
        if settingsStore.floatingIndicatorEnabled {
            floatingIndicatorController.show()
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
                    
                    if mode == .directInsert && !self.outputManager.checkAccessibilityPermission() {
                        AlertManager.shared.showAccessibilityPermissionAlert()
                    }
                    
                    if self.settingsStore.floatingIndicatorEnabled {
                        self.floatingIndicatorController.show()
                    } else {
                        self.floatingIndicatorController.hide()
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
        floatingIndicatorController.updateRecordingState(isRecording: true)
        
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
        floatingIndicatorController.updateRecordingState(isRecording: false)
        
        defer {
            isProcessing = false
            recordingStartTime = nil
            statusBarController.setIdleState()
            statusBarController.updateMenuState()
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
}
