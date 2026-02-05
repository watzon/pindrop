//
//  WhisperKitEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation
import WhisperKit

@MainActor
public final class WhisperKitEngine: TranscriptionEngine, CapabilityReporting {
    
    public static var capabilities: AudioEngineCapabilities {
        [.transcription, .wordTimestamps, .languageDetection, .voiceActivityDetection]
    }
    
    /// Errors that can occur during transcription operations
    public enum EngineError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model is not loaded"
            case .invalidAudioData:
                return "Invalid audio data"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
    
    /// Current state of the engine
    public private(set) var state: TranscriptionEngineState = .unloaded
    
    /// Current error, if any
    public private(set) var error: Error?
    
    /// The underlying WhisperKit pipeline
    private var whisperKit: WhisperKit?
    
    /// Currently loading task
    private var loadingTask: Task<Void, Error>?
    
    /// Currently transcribing task
    private var transcribingTask: Task<String, Error>?
    
    public init() {}
    
    /// Load a model from a local file path
    public func loadModel(path: String) async throws {
        guard state != .loading else { return }
        
        state = .loading
        error = nil
        
        do {
            let config = WhisperKitConfig(
                modelFolder: path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
            )
            
            whisperKit = try await WhisperKit(config)
            try await whisperKit?.loadModels()
            
            state = .ready
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }
    
    /// Load a model by name, optionally downloading if not present locally
    public func loadModel(name: String, downloadBase: URL? = nil) async throws {
        guard state != .loading else { return }
        
        state = .loading
        error = nil
        
        do {
            let config = WhisperKitConfig(
                model: name,
                downloadBase: downloadBase,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
            )
            
            whisperKit = try await WhisperKit(config)
            try await whisperKit?.loadModels()
            
            state = .ready
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }
    
    /// Transcribe audio data to text
    public func transcribe(audioData: Data) async throws -> String {
        guard state == .ready else {
            throw EngineError.modelNotLoaded
        }
        
        guard !audioData.isEmpty else {
            throw EngineError.invalidAudioData
        }
        
        guard transcribingTask == nil else {
            throw EngineError.transcriptionFailed("Transcription already in progress")
        }
        
        state = .transcribing
        
        do {
            // Convert Data to [Float] for WhisperKit
            let samples = audioData.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }
            
            guard let whisperKit = whisperKit else {
                throw EngineError.modelNotLoaded
            }
            
            let results = try await whisperKit.transcribe(audioArray: samples)
            guard let result = results.first else {
                throw EngineError.transcriptionFailed("No transcription result")
            }
            
            state = .ready
            return result.text
        } catch {
            state = .ready
            self.error = error
            throw error
        }
    }
    
    /// Unload the model and free resources
    public func unloadModel() async {
        transcribingTask?.cancel()
        transcribingTask = nil
        
        whisperKit = nil
        error = nil
        state = .unloaded
    }
    
    // MARK: - Convenience Methods for Tests
    
    /// Load a model by name (convenience method for tests)
    public func loadModel(modelName: String) async throws {
        try await loadModel(name: modelName, downloadBase: nil)
    }
    
    /// Load a model from a path (convenience method for tests)
    public func loadModel(modelPath: String) async throws {
        try await loadModel(path: modelPath)
    }
}
