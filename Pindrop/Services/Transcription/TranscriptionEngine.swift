//
//  TranscriptionEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

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
    func transcribe(audioData: Data) async throws -> String
    
    /// Unload the model and free resources
    func unloadModel() async
}


