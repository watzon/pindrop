//
//  ParakeetEngine.swift
//  Pindrop
//
//  Created on 2026-01-30.
//

import Foundation
import FluidAudio

@MainActor
public final class ParakeetEngine: TranscriptionEngine, CapabilityReporting {
    
    public static var capabilities: AudioEngineCapabilities {
        [.transcription, .streamingTranscription, .voiceActivityDetection, .speakerDiarization]
    }
    
    public enum EngineError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case downloadFailed(String)
        case initializationFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model is not loaded"
            case .invalidAudioData:
                return "Invalid audio data"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .downloadFailed(let message):
                return "Model download failed: \(message)"
            case .initializationFailed(let message):
                return "Initialization failed: \(message)"
            }
        }
    }
    
    public private(set) var state: TranscriptionEngineState = .unloaded
    public private(set) var error: Error?
    
    private var asrManager: AsrManager?
    private var transcribingTask: Task<String, Error>?
    private var ctcModels: CtcModels?
    private var configuredVocabularyTerms: [String] = []
    
    public init() {}
    
    public func loadModel(path: String) async throws {
        guard state != .loading else { return }
        
        state = .loading
        error = nil
        
        do {
            throw EngineError.initializationFailed("Loading from path not supported for Parakeet. Use loadModel(name:downloadBase:) instead.")
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }
    
    public func loadModel(name: String, downloadBase: URL? = nil) async throws {
        guard state != .loading else { return }
        
        state = .loading
        error = nil
        
        do {
            let version: AsrModelVersion = name.contains("v3") ? .v3 : .v2
            let models = try await AsrModels.downloadAndLoad(version: version)
            
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            asrManager = manager
            state = .ready
        } catch {
            self.error = error
            state = .error
            throw EngineError.downloadFailed(error.localizedDescription)
        }
    }
    
    public func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        guard state == .ready else {
            throw EngineError.modelNotLoaded
        }
        
        guard !audioData.isEmpty else {
            throw EngineError.invalidAudioData
        }
        
        guard transcribingTask == nil else {
            throw EngineError.transcriptionFailed("Transcription already in progress")
        }
        
        guard let asrManager = asrManager else {
            throw EngineError.modelNotLoaded
        }
        
        state = .transcribing
        
        do {
            let samples = audioData.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }

            try await configureVocabularyBoostingIfNeeded(
                options.customVocabularyWords,
                asrManager: asrManager
            )
            let result = try await asrManager.transcribe(samples, source: .microphone)
            
            state = .ready
            return result.text
        } catch {
            state = .ready
            self.error = error
            throw EngineError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    public func unloadModel() async {
        transcribingTask?.cancel()
        transcribingTask = nil
        
        asrManager = nil
        ctcModels = nil
        configuredVocabularyTerms = []
        error = nil
        state = .unloaded
    }
    
    public func loadModel(modelName: String) async throws {
        try await loadModel(name: modelName, downloadBase: nil)
    }
    
    public func loadModel(modelPath: String) async throws {
        try await loadModel(path: modelPath)
    }

    private func configureVocabularyBoostingIfNeeded(
        _ words: [String],
        asrManager: AsrManager
    ) async throws {
        let normalizedWords = normalizedVocabularyWords(words)

        guard !normalizedWords.isEmpty else {
            if !configuredVocabularyTerms.isEmpty {
                asrManager.disableVocabularyBoosting()
                configuredVocabularyTerms = []
            }
            return
        }

        guard normalizedWords != configuredVocabularyTerms else {
            return
        }

        let vocabulary = CustomVocabularyContext(
            terms: normalizedWords.map { CustomVocabularyTerm(text: $0) }
        )

        if ctcModels == nil {
            ctcModels = try await CtcModels.downloadAndLoad()
        }

        guard let ctcModels else {
            throw EngineError.transcriptionFailed("Failed to load vocabulary boosting models")
        }

        try await asrManager.configureVocabularyBoosting(
            vocabulary: vocabulary,
            ctcModels: ctcModels
        )
        configuredVocabularyTerms = normalizedWords
    }

    private func normalizedVocabularyWords(_ words: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            normalized.append(trimmed)
        }

        return normalized
    }
}
