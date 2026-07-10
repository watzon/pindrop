//
//  TranscriptionEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

public struct TranscriptionOptions: Sendable, Equatable {
    public let language: AppLanguage
    /// Vocabulary words for WhisperKit initial-prompt biasing. Empty = no bias.
    public let vocabularyBiasWords: [String]

    public init(language: AppLanguage = .automatic, vocabularyBiasWords: [String] = []) {
        self.language = language
        self.vocabularyBiasWords = vocabularyBiasWords
    }
}

/// Represents the current state of a transcription engine
public enum TranscriptionEngineState: Equatable {
    case unloaded
    case loading
    case ready
    case transcribing
    case error
}

/// Protocol abstraction for speech-to-text engines
/// Allows TranscriptionService to work with multiple backends (WhisperKit, Parakeet, etc.)
@MainActor
public protocol TranscriptionEngine: AnyObject {
    /// Current state of the engine
    var state: TranscriptionEngineState { get }
    
    /// Load a model from a local file path
    /// - Parameter path: Absolute path to the model directory
    func loadModel(path: String) async throws
    
    /// Load a model by name, optionally downloading if not present locally
    /// - Parameters:
    ///   - name: Model identifier (e.g., "tiny", "base", "small")
    ///   - downloadBase: Optional URL for downloading models if not cached locally
    func loadModel(name: String, downloadBase: URL?) async throws
    
    /// Transcribe audio data to text
    /// - Parameter audioData: Raw audio data (expected format: 16kHz mono PCM Float32)
    /// - Returns: Transcribed text
    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String

    /// Detect the spoken language in raw samples, when supported.
    /// - Parameters:
    ///   - samples: Raw audio samples (expected format: 16kHz mono PCM Float32)
    ///   - sampleRate: Sample rate for the provided samples
    /// - Returns: A concrete app language, or nil when detection is unavailable.
    func detectLanguage(samples: [Float], sampleRate: Int) async throws -> AppLanguage?
    
    /// Unload the model and free resources
    func unloadModel() async
}

public extension TranscriptionEngine {
    func transcribe(audioData: Data) async throws -> String {
        try await transcribe(audioData: audioData, options: TranscriptionOptions())
    }

    func detectLanguage(samples: [Float], sampleRate: Int) async throws -> AppLanguage? {
        nil
    }
}
