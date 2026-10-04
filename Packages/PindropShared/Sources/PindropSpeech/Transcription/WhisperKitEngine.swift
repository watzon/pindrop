//
//  WhisperKitEngine.swift
//  PindropSpeech
//
//  Created on 2026-01-30.
//

import Foundation
import PindropCore
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
    static func loadConfiguration(
        model: String? = nil,
        downloadBase: URL? = nil,
        modelFolder: String? = nil,
        download: Bool = true
    ) -> WhisperKitConfig {
        WhisperKitConfig(
            model: model,
            downloadBase: downloadBase,
            modelFolder: modelFolder,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: download
        )
    }

    /// Load a model from a local file path
    public func loadModel(path: String) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        let wallStart = CFAbsoluteTimeGetCurrent()
        Log.boot.info("WhisperKitEngine.loadModel(path) begin")

        do {
            // Core ML can evict its device-specialization cache after an OS update.
            // Prewarming serializes specialization before the normal load, avoiding
            // the large peak-memory spike that can stall non-Tiny models.
            let config = Self.loadConfiguration(
                modelFolder: path,
                download: false
            )

            let initStart = CFAbsoluteTimeGetCurrent()
            whisperKit = try await WhisperKit(config)
            Log.boot.info("WhisperKitEngine(path) prewarm and load elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - initStart)) total=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - wallStart))")

            state = .ready
        } catch {
            Log.boot.error("WhisperKitEngine.loadModel(path) failed after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - wallStart)) \(error.localizedDescription)")
            self.error = error
            state = .error
            throw error
        }
    }

    /// Load a model by name, optionally downloading if not present locally.
    /// Protocol-conforming entry point (always allows download when the model is missing).
    ///
    /// - Parameter downloadBase: Host-injected `ModelStorageLocations.pindropApplicationSupportRoot`.
    ///   WhisperKit stores variants under `models/argmaxinc/whisperkit-coreml` beneath this root.
    public func loadModel(name: String, downloadBase: URL?) async throws {
        try await loadModel(name: name, downloadBase: downloadBase, download: true)
    }

    /// Load a model by name with an explicit download flag.
    /// - Parameters:
    ///   - name: WhisperKit model name (e.g. `"tiny"`).
    ///   - downloadBase: Injected Pindrop application-support root. When `download` is false,
    ///     only this tree is consulted. Never reconstructed inside the engine.
    ///   - download: When false, WhisperKit will not hit the network (unit-test / offline path).
    public func loadModel(name: String, downloadBase: URL?, download: Bool) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        let wallStart = CFAbsoluteTimeGetCurrent()
        Log.boot.info("WhisperKitEngine.loadModel(name) begin name=\(name) downloadBaseProvided=\(downloadBase != nil) download=\(download)")

        do {
            let config = Self.loadConfiguration(
                model: name,
                downloadBase: downloadBase,
                download: download
            )

            let initStart = CFAbsoluteTimeGetCurrent()
            whisperKit = try await WhisperKit(config)
            Log.boot.info("WhisperKitEngine prewarm and load elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - initStart)) total=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - wallStart))")

            state = .ready
        } catch {
            Log.boot.error("WhisperKitEngine.loadModel(name) failed after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - wallStart)) \(error.localizedDescription)")
            self.error = error
            state = .error
            throw error
        }
    }

    /// Transcribe audio data to text
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

        state = .transcribing

        do {
            // Convert Data to [Float] for WhisperKit
            let samples = audioData.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }

            guard let whisperKit = whisperKit else {
                throw EngineError.modelNotLoaded
            }

            var decodeOptions = DecodingOptions(
                task: .transcribe,
                language: options.language.whisperLanguageCode
            )
            decodeOptions.detectLanguage = options.language == .automatic
            decodeOptions.usePrefillPrompt = true

            // Vocabulary biasing via decoder promptTokens; empty vocabulary is a no-op.
            // WhisperKit 0.15.0 returned an empty transcript whenever promptTokens
            // were set (argmaxinc/argmax-oss-swift#372, fixed in 1.1.0 by PR #514).
            // Do not move the dependency below 1.1.0 while this block exists.
            if let tokenizer = whisperKit.tokenizer {
                decodeOptions.promptTokens = Self.vocabularyPromptTokens(
                    words: options.vocabularyBiasWords,
                    sampleCount: samples.count
                ) { text in
                    tokenizer.encode(text: text)
                        .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                }
            }

            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
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

    /// Whisper conditions on at most half of its 448-token context, less the
    /// start-of-previous token. WhisperKit keeps only the last tokens of a longer
    /// prompt, which drops the highest-priority words first.
    static let maxVocabularyPromptTokens = 223

    /// One 30 s Whisper window at 16 kHz. With promptTokens set, WhisperKit turns
    /// its timestamp rules off, and a clip that needs more than one window can
    /// lose whole spans of speech.
    static let maxVocabularyBiasSampleCount = 30 * 16_000

    /// Prompt tokens for vocabulary biasing, or `nil` when no bias is safe to apply.
    /// Drops the lowest-priority words (the end of `words`) until the prompt fits
    /// the token budget. This matters for CJK words, which use many tokens each.
    static func vocabularyPromptTokens(
        words: [String],
        sampleCount: Int,
        encode: (String) -> [Int]
    ) -> [Int]? {
        guard sampleCount <= maxVocabularyBiasSampleCount else { return nil }

        var words = words
        while let prompt = VocabularyBiasPrompt.assemblePrompt(words: words) {
            let tokens = encode(" " + prompt.trimmingCharacters(in: .whitespaces))
            if tokens.count <= maxVocabularyPromptTokens {
                return tokens.isEmpty ? nil : tokens
            }
            words.removeLast()
        }
        return nil
    }

    /// Detect the spoken language from full-clip samples so diarized segments can
    /// share one stable language decision.
    public func detectLanguage(samples: [Float], sampleRate: Int) async throws -> AppLanguage? {
        guard state == .ready else {
            throw EngineError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw EngineError.invalidAudioData
        }

        guard let whisperKit else {
            throw EngineError.modelNotLoaded
        }

        state = .transcribing

        do {
            let result = try await whisperKit.detectLangauge(audioArray: samples)
            state = .ready
            return Self.appLanguage(forWhisperLanguageCode: result.language)
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

    /// Load a model by name (convenience for callers that already own a download base).
    /// Unit tests must pass `download: false` (and/or a nonexistent path via
    /// `loadModel(path:)`) so the Unit plan never performs a network download.
    public func loadModel(modelName: String, downloadBase: URL? = nil, download: Bool = true) async throws {
        try await loadModel(name: modelName, downloadBase: downloadBase, download: download)
    }

    /// Load a model from a path (convenience method for tests)
    public func loadModel(modelPath: String) async throws {
        try await loadModel(path: modelPath)
    }

    /// Maps a Whisper language token (e.g. "hi", "ml") back to `AppLanguage`.
    /// Internal for unit tests; production only calls this from `detectLanguage`.
    public static func appLanguage(forWhisperLanguageCode code: String) -> AppLanguage? {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCode.isEmpty else { return nil }

        return AppLanguage.allCases.first { language in
            language != .automatic &&
                (language.whisperLanguageCode?.lowercased() == normalizedCode ||
                 language.rawValue.lowercased() == normalizedCode)
        }
    }
}
