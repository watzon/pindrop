//
//  TranscriptionPorts.swift
//  Pindrop
//
//  Created on 2026-03-28.
//

import AVFoundation
import Foundation

struct TranscriptionSettingsSnapshot: Sendable, Equatable {
    let selectedLanguage: AppLanguage
    let selectedModelName: String
    let aiEnhancementEnabled: Bool
    let streamingFeatureEnabled: Bool
    let diarizationFeatureEnabled: Bool

    init(
        selectedLanguage: AppLanguage,
        selectedModelName: String,
        aiEnhancementEnabled: Bool,
        streamingFeatureEnabled: Bool,
        diarizationFeatureEnabled: Bool
    ) {
        self.selectedLanguage = selectedLanguage
        self.selectedModelName = selectedModelName
        self.aiEnhancementEnabled = aiEnhancementEnabled
        self.streamingFeatureEnabled = streamingFeatureEnabled
        self.diarizationFeatureEnabled = diarizationFeatureEnabled
    }
}

@MainActor
public protocol TranscriptionEnginePort: AnyObject {
    var state: TranscriptionEngineState { get }

    func loadModel(path: String) async throws
    func loadModel(name: String, downloadBase: URL?) async throws
    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String
    func unloadModel() async
}

@MainActor
public protocol StreamingTranscriptionEnginePort: AnyObject {
    var state: StreamingTranscriptionState { get }

    func loadModel(name: String) async throws
    func unloadModel() async

    func startStreaming() async throws
    func stopStreaming() async throws -> String
    func pauseStreaming() async
    func resumeStreaming() async throws

    func processAudioChunk(_ samples: [Float]) async throws
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws

    func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback)
    func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback)

    func reset() async
}

@MainActor
public protocol SpeakerDiarizerPort: AnyObject {
    var state: SpeakerDiarizerState { get }
    var mode: DiarizationMode { get }

    func loadModels() async throws
    func unloadModels() async

    func diarize(audioData: Data) async throws -> DiarizationResult
    func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult

    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float

    func registerKnownSpeaker(_ speaker: Speaker) async throws
    func clearKnownSpeakers() async
}

@MainActor
protocol ModelCatalogProviding: AnyObject {
    var availableModels: [ModelManager.WhisperModel] { get }
    var recommendedModels: [ModelManager.WhisperModel] { get }

    func recommendedModels(for language: AppLanguage) -> [ModelManager.WhisperModel]
    func isModelDownloaded(_ modelName: String) -> Bool
}

protocol SettingsSnapshotProvider {
    @MainActor
    func transcriptionSettingsSnapshot() -> TranscriptionSettingsSnapshot
}

@MainActor
protocol TranscriptionOrchestrating: AnyObject {
    var state: TranscriptionService.State { get }
    var error: Error? { get }

    func loadModel(modelName: String, provider: ModelManager.ModelProvider) async throws
    func loadModel(modelPath: String) async throws
    func unloadModel() async

    func transcribe(audioData: Data) async throws -> String
    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String
    func transcribe(audioData: Data, diarizationEnabled: Bool) async throws -> TranscriptionOutput
    func transcribe(
        audioData: Data,
        diarizationEnabled: Bool,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput

    func prepareStreamingEngine() async throws
    func startStreaming() async throws
    func processStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws
    func stopStreaming() async throws -> String
    func cancelStreaming() async
    func setStreamingCallbacks(
        onPartial: (@Sendable (String) -> Void)?,
        onFinalUtterance: (@Sendable (String) -> Void)?
    )
}
