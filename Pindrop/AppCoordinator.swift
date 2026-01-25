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
    
    init(modelContext: ModelContext) {
        self.permissionManager = PermissionManager()
        self.audioRecorder = AudioRecorder(permissionManager: permissionManager)
        self.transcriptionService = TranscriptionService()
        self.modelManager = ModelManager()
        self.aiEnhancementService = AIEnhancementService()
        self.hotkeyManager = HotkeyManager()
        self.outputManager = OutputManager()
        self.historyStore = HistoryStore(modelContext: modelContext)
        self.settingsStore = SettingsStore()
        
        self.statusBarController = StatusBarController(
            audioRecorder: audioRecorder,
            settingsStore: settingsStore
        )
        self.floatingIndicatorController = FloatingIndicatorController()
        
        setupHotkeys()
        observeSettings()
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        do {
            let modelName = settingsStore.selectedModel
            try await transcriptionService.loadModel(modelName: modelName)
        } catch {
            self.error = error
            print("Failed to load transcription model: \(error)")
        }
        
        if settingsStore.floatingIndicatorEnabled {
            floatingIndicatorController.show()
        }
    }
    
    // MARK: - Hotkey Setup
    
    private func setupHotkeys() {
        let pushToTalkKeyCode: UInt32 = 17
        let pushToTalkModifiers: HotkeyManager.ModifierFlags = [.command, .shift]
        
        _ = hotkeyManager.registerHotkey(
            keyCode: pushToTalkKeyCode,
            modifiers: pushToTalkModifiers,
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
        
        let toggleKeyCode: UInt32 = 15
        let toggleModifiers: HotkeyManager.ModifierFlags = [.command, .shift]
        
        _ = hotkeyManager.registerHotkey(
            keyCode: toggleKeyCode,
            modifiers: toggleModifiers,
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
    
    // MARK: - Settings Observation
    
    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    let mode: OutputMode = self.settingsStore.outputMode == "clipboard" ? .clipboard : .directInsert
                    self.outputManager.setOutputMode(mode)
                    
                    if self.settingsStore.floatingIndicatorEnabled {
                        self.floatingIndicatorController.show()
                    } else {
                        self.floatingIndicatorController.hide()
                    }
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
            print("Failed to start recording: \(error)")
        }
    }
    
    private func handlePushToTalkEnd() async {
        guard isRecording else { return }
        
        do {
            try await stopRecordingAndTranscribe()
        } catch {
            self.error = error
            print("Failed to stop recording: \(error)")
        }
    }
    
    private func handleToggleRecording() async {
        if isRecording {
            do {
                try await stopRecordingAndTranscribe()
            } catch {
                self.error = error
                print("Failed to stop recording: \(error)")
            }
        } else if !isProcessing {
            do {
                try await startRecording()
            } catch {
                self.error = error
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func startRecording() async throws {
        isRecording = true
        recordingStartTime = Date()
        
        statusBarController.updateMenuState()
        floatingIndicatorController.updateRecordingState(isRecording: true)
        
        try await audioRecorder.startRecording()
    }
    
    private func stopRecordingAndTranscribe() async throws {
        guard let startTime = recordingStartTime else { return }
        
        isRecording = false
        isProcessing = true
        
        statusBarController.setProcessingState()
        floatingIndicatorController.updateRecordingState(isRecording: false)
        
        let audioData = try await audioRecorder.stopRecording()
        let duration = Date().timeIntervalSince(startTime)
        let transcribedText = try await transcriptionService.transcribe(audioData: audioData)
        
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
                print("AI enhancement failed: \(error)")
            }
        }
        
        try await outputManager.output(finalText)
        
        do {
            try historyStore.save(
                text: finalText,
                duration: duration,
                modelUsed: settingsStore.selectedModel
            )
        } catch {
            print("Failed to save to history: \(error)")
        }
        
        isProcessing = false
        recordingStartTime = nil
        statusBarController.setIdleState()
    }
}
