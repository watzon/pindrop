//
//  TranscriptionEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation

public struct TranscriptionOptions: Sendable, Equatable {
    public let language: AppLanguage
    public let customVocabularyWords: [String]

    public init(
        language: AppLanguage = .automatic,
        customVocabularyWords: [String] = []
    ) {
        self.language = language
        self.customVocabularyWords = customVocabularyWords
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
public protocol TranscriptionEngine: TranscriptionEnginePort {
}

public extension TranscriptionEngine {
    func transcribe(audioData: Data) async throws -> String {
        try await transcribe(audioData: audioData, options: TranscriptionOptions())
    }
}
