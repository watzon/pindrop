//
//  NativeTranscriptionAdapters.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import AVFoundation
import Foundation

@MainActor
final class WhisperKitTranscriptionAdapter: TranscriptionEnginePort {
    private let engine: WhisperKitEngine

    init() {
        self.engine = WhisperKitEngine()
    }

    init(engine: WhisperKitEngine) {
        self.engine = engine
    }

    var state: TranscriptionEngineState { engine.state }

    func loadModel(path: String) async throws {
        try await engine.loadModel(path: path)
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        try await engine.loadModel(name: name, downloadBase: downloadBase)
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await engine.transcribe(audioData: audioData, options: options)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }
}

@MainActor
final class ParakeetTranscriptionAdapter: TranscriptionEnginePort {
    private let engine: ParakeetEngine

    init() {
        self.engine = ParakeetEngine()
    }

    init(engine: ParakeetEngine) {
        self.engine = engine
    }

    var state: TranscriptionEngineState { engine.state }

    func loadModel(path: String) async throws {
        try await engine.loadModel(path: path)
    }

    func loadModel(name: String, downloadBase: URL?) async throws {
        try await engine.loadModel(name: name, downloadBase: downloadBase)
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await engine.transcribe(audioData: audioData, options: options)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }
}

@MainActor
final class ParakeetStreamingAdapter: StreamingTranscriptionEnginePort {
    private let engine: ParakeetStreamingEngine

    init() {
        self.engine = ParakeetStreamingEngine()
    }

    init(engine: ParakeetStreamingEngine) {
        self.engine = engine
    }

    var state: StreamingTranscriptionState { engine.state }

    func loadModel(name: String) async throws {
        try await engine.loadModel(name: name)
    }

    func unloadModel() async {
        await engine.unloadModel()
    }

    func startStreaming() async throws {
        try await engine.startStreaming()
    }

    func stopStreaming() async throws -> String {
        try await engine.stopStreaming()
    }

    func pauseStreaming() async {
        await engine.pauseStreaming()
    }

    func resumeStreaming() async throws {
        try await engine.resumeStreaming()
    }

    func processAudioChunk(_ samples: [Float]) async throws {
        try await engine.processAudioChunk(samples)
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        try await engine.processAudioBuffer(buffer)
    }

    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
        engine.setTranscriptionCallback(callback)
    }

    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        engine.setEndOfUtteranceCallback(callback)
    }

    func reset() async {
        await engine.reset()
    }
}

@MainActor
final class MacOSModelCatalogAdapter: ModelCatalogProviding {
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    var availableModels: [ModelManager.WhisperModel] {
        modelManager.availableModels
    }

    var recommendedModels: [ModelManager.WhisperModel] {
        modelManager.recommendedModels
    }

    func recommendedModels(for language: AppLanguage) -> [ModelManager.WhisperModel] {
        modelManager.recommendedModels(for: language)
    }

    func isModelDownloaded(_ modelName: String) -> Bool {
        modelManager.isModelDownloaded(modelName)
    }
}

@MainActor
final class MacOSSettingsSnapshotAdapter: SettingsSnapshotProvider {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func transcriptionSettingsSnapshot() -> TranscriptionSettingsSnapshot {
        TranscriptionSettingsSnapshot(
            selectedLanguage: settingsStore.selectedAppLanguage,
            selectedModelName: settingsStore.selectedModel,
            aiEnhancementEnabled: settingsStore.aiEnhancementEnabled,
            streamingFeatureEnabled: settingsStore.streamingFeatureEnabled,
            diarizationFeatureEnabled: settingsStore.diarizationFeatureEnabled
        )
    }
}
