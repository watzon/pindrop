//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AVFoundation
import Foundation
import os.log

@MainActor
@Observable
class TranscriptionService {
    
    enum State: Equatable {
        case unloaded
        case loading
        case ready
        case transcribing
        case error
    }
    
    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case modelLoadFailed(String)
        case engineSwitchDuringTranscription
        case streamingModelNotAvailable(String)
        case streamingNotReady
        case streamingStartFailed(String)
        case streamingProcessingFailed(String)
        case streamingStopFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM format."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
            case .engineSwitchDuringTranscription:
                return "Cannot switch engines during active transcription"
            case .streamingModelNotAvailable(let path):
                return "Streaming model not available at path: \(path)"
            case .streamingNotReady:
                return "Streaming engine not ready. Call prepareStreamingEngine() first."
            case .streamingStartFailed(let message):
                return "Failed to start streaming transcription: \(message)"
            case .streamingProcessingFailed(let message):
                return "Failed to process streaming audio: \(message)"
            case .streamingStopFailed(let message):
                return "Failed to stop streaming transcription: \(message)"
            }
        }
    }
    
    private(set) var state: State = .unloaded
    private(set) var error: Error?
    private var engine: (any TranscriptionEngine)?
    private var streamingEngine: (any StreamingTranscriptionEngine)?
    private var currentProvider: ModelManager.ModelProvider?
    private var streamingPartialCallback: (@Sendable (String) -> Void)?
    private var streamingFinalUtteranceCallback: (@Sendable (String) -> Void)?
    private let streamingEngineFactory: @MainActor () -> any StreamingTranscriptionEngine

    init(
        streamingEngineFactory: @escaping @MainActor () -> any StreamingTranscriptionEngine = {
            ParakeetStreamingEngine()
        }
    ) {
        self.streamingEngineFactory = streamingEngineFactory
    }
    
    func loadModel(modelName: String = "tiny", provider: ModelManager.ModelProvider = .whisperKit) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }
        
        if currentProvider != nil && currentProvider != provider {
            await unloadModel()
        }
        
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model: \(modelName) with provider: \(provider.rawValue)...")
        
        do {
            let newEngine: any TranscriptionEngine
            switch provider {
            case .whisperKit:
                newEngine = WhisperKitEngine()
            case .parakeet:
                newEngine = ParakeetEngine()
            default:
                throw TranscriptionError.modelLoadFailed("Provider \(provider.rawValue) not supported locally")
            }
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(name: modelName, downloadBase: self.getDownloadBase())
                }
                
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }
                
                try await group.next()
                group.cancelAll()
            }
            
            engine = newEngine
            currentProvider = provider
            Log.transcription.info("Model loaded successfully with \(provider.rawValue) engine")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }
    
    func loadModel(modelPath: String) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }
        
        if currentProvider != nil {
            await unloadModel()
        }
        
        state = .loading
        error = nil
        
        Log.transcription.info("Loading model from path: \(modelPath) with prewarm enabled...")
        
        do {
            let newEngine = WhisperKitEngine()
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await newEngine.loadModel(path: modelPath)
                }
                
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw TranscriptionError.modelLoadFailed("Model loading timed out after 120s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings.")
                }
                
                try await group.next()
                group.cancelAll()
            }
            
            engine = newEngine
            currentProvider = .whisperKit
            Log.transcription.info("Model loaded and prewarmed successfully")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    func transcribe(audioData: Data) async throws -> String {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")
        
        guard let engine = engine else {
            throw TranscriptionError.modelNotLoaded
        }
        
        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }
        
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }
        
        state = .transcribing
        
        do {
            let floatCount = audioData.count / MemoryLayout<Float>.size
            let duration = Double(floatCount) / 16000.0
            let providerName = currentProvider?.rawValue ?? "unknown"
            Log.transcription.info("Transcribing \(floatCount) samples (\(String(format: "%.2f", duration))s) using \(providerName)")
            
            let startTime = Date()
            let result = try await engine.transcribe(audioData: audioData)
            
            let elapsed = Date().timeIntervalSince(startTime)
            Log.transcription.info("Transcription completed in \(String(format: "%.2f", elapsed))s")
            
            state = .ready
            
            Log.transcription.debug("Result redacted (chars=\(result.count))")
            return result
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            state = .ready
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    func unloadModel() async {
        await engine?.unloadModel()
        await streamingEngine?.unloadModel()
        engine = nil
        streamingEngine = nil
        currentProvider = nil
        state = .unloaded
        error = nil
    }

    func setStreamingCallbacks(
        onPartial: (@Sendable (String) -> Void)? = nil,
        onFinalUtterance: (@Sendable (String) -> Void)? = nil
    ) {
        streamingPartialCallback = onPartial
        streamingFinalUtteranceCallback = onFinalUtterance
        applyStreamingCallbacks()
    }

    func prepareStreamingEngine() async throws {
        if streamingEngine == nil {
            streamingEngine = streamingEngineFactory()
            applyStreamingCallbacks()
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        switch streamingEngine.state {
        case .ready, .streaming, .paused:
            if state == .unloaded || state == .error {
                state = .ready
            }
            return
        case .loading:
            return
        case .unloaded, .error:
            break
        }

        let modelPath = FeatureModelType.streaming.repoFolderName
        do {
            try await streamingEngine.loadModel(name: modelPath)
            if state == .unloaded || state == .error {
                state = .ready
            }
        } catch {
            let path = getStreamingModelBase()
                .appendingPathComponent(modelPath, isDirectory: true)
                .path
            let streamingError = TranscriptionError.streamingModelNotAvailable(path)
            self.error = streamingError
            state = .error
            throw streamingError
        }
    }

    func startStreaming() async throws {
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        do {
            try await prepareStreamingEngine()
            guard let streamingEngine else {
                throw TranscriptionError.streamingNotReady
            }
            try await streamingEngine.startStreaming()
            state = .transcribing
            error = nil
        } catch let error as TranscriptionError {
            self.error = error
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStartFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func processStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard state == .transcribing else {
            throw TranscriptionError.streamingNotReady
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            try await streamingEngine.processAudioBuffer(buffer)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingProcessingFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func stopStreaming() async throws -> String {
        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            let finalText = try await streamingEngine.stopStreaming()
            state = .ready
            return finalText
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStopFailed(error.localizedDescription)
            self.error = streamingError
            state = .ready
            throw streamingError
        }
    }

    func cancelStreaming() async {
        await streamingEngine?.reset()
        if engine != nil || streamingEngine != nil {
            state = .ready
        } else {
            state = .unloaded
        }
    }
    
    private func getDownloadBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }

    private func getStreamingModelBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func applyStreamingCallbacks() {
        guard let streamingEngine else { return }

        streamingEngine.setTranscriptionCallback { [weak self] result in
            guard !result.isFinal else { return }
            Task { @MainActor [weak self] in
                self?.streamingPartialCallback?(result.text)
            }
        }

        streamingEngine.setEndOfUtteranceCallback { [weak self] text in
            Task { @MainActor [weak self] in
                self?.streamingFinalUtteranceCallback?(text)
            }
        }
    }
    
    private func dataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)
        
        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                floatArray[i] = floatBuffer[i]
            }
        }
        
        return floatArray
    }
}
