//
//  ParakeetEngine.swift
//  PindropSpeech
//
//  Created on 2026-01-30.
//

import FluidAudio
import Foundation
import PindropCore

@MainActor
public final class ParakeetEngine: TranscriptionEngine, CapabilityReporting {

    public nonisolated static var capabilities: AudioEngineCapabilities {
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

    public nonisolated static let orukeetModelName = "orukeet-coreml-preview"

    public init() {}

    public func loadModel(path: String) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        do {
            throw EngineError.initializationFailed(
                "Loading from path not supported for Parakeet. Use loadModel(name:downloadBase:) with the injected repo directory."
            )
        } catch {
            self.error = error
            state = .error
            throw error
        }
    }

    /// Load (and download if needed) a Parakeet model into an injected repo directory.
    ///
    /// - Parameters:
    ///   - name: Catalog model name (e.g. `"parakeet-tdt-0.6b-v3"`). Version is inferred from the name.
    ///   - downloadBase: Exact repository directory
    ///     `fluidAudioModelsRoot.appendingPathComponent(version.repo.folderName)`.
    ///     Required. Never reconstructed from Application Support defaults.
    public func loadModel(name: String, downloadBase: URL?) async throws {
        guard state != .loading else { return }

        state = .loading
        error = nil

        do {
            guard let modelDirectory = downloadBase else {
                throw EngineError.initializationFailed(
                    "Parakeet requires an injected model directory (downloadBase)."
                )
            }

            let models: AsrModels
            #if os(macOS)
            if name == Self.orukeetModelName {
                models = try await OrukeetModelStore.prepare(at: modelDirectory)
            } else {
                models = try await AsrModels.downloadAndLoad(to: modelDirectory, version: Self.modelVersion(forName: name))
            }
            #else
            guard name != Self.orukeetModelName else {
                throw EngineError.initializationFailed("Orukeet is currently available on macOS only.")
            }
            models = try await AsrModels.downloadAndLoad(to: modelDirectory, version: Self.modelVersion(forName: name))
            #endif

            // FluidAudio 0.15+: AsrManager takes models at init (or via loadModels),
            // replacing the retired `initialize(models:)` entry point.
            let manager = AsrManager(config: .default, models: models)
            try await manager.loadModels(models)

            asrManager = manager
            state = .ready
        } catch let engineError as EngineError {
            self.error = engineError
            state = .error
            throw engineError
        } catch {
            let mapped = EngineError.downloadFailed(error.localizedDescription)
            self.error = mapped
            state = .error
            throw mapped
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

            // FluidAudio 0.15+: batch transcribe requires an explicit TDT decoder state.
            let decoderLayers = await asrManager.decoderLayerCount
            var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
            let result = try await asrManager.transcribe(samples, decoderState: &decoderState)

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
        error = nil
        state = .unloaded
    }

    public func loadModel(modelName: String, downloadBase: URL) async throws {
        try await loadModel(name: modelName, downloadBase: downloadBase)
    }

    public func loadModel(modelPath: String) async throws {
        try await loadModel(path: modelPath)
    }

    /// Exact repository directory for a Parakeet version under an injected FluidAudio models root.
    /// Hosts and factories should pass this URL as `downloadBase`.
    /// Uses public `Repo` folder names (FluidAudio's `AsrModelVersion.repo` is module-internal).
    public nonisolated static func modelDirectory(
        for version: AsrModelVersion,
        fluidAudioModelsRoot: URL
    ) -> URL {
        let folderName: String
        switch version {
        case .v2:
            folderName = Repo.parakeetV2.folderName
        case .v3:
            folderName = Repo.parakeetV3.folderName
        case .tdtCtc110m:
            folderName = Repo.parakeetTdtCtc110m.folderName
        case .tdtJa:
            folderName = Repo.parakeetJa.folderName
        }
        return fluidAudioModelsRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Map a catalog model name to the FluidAudio `AsrModelVersion` used for download/load.
    /// Pure string matching - never reads `AsrModelVersion.repo` (module-internal).
    /// Unknown names default to `.v2`, matching ModelManager's local-path fallback.
    public nonisolated static func modelVersion(forName name: String) -> AsrModelVersion {
        let lowered = name.lowercased()
        // More specific identifiers first so "tdt-ctc-110m" is not misread as v2/v3.
        if lowered.contains("tdt-ctc")
            || lowered.contains("tdtctc")
            || lowered.contains("tdt_ctc")
            || lowered.contains("110m") {
            return .tdtCtc110m
        }
        if lowered.contains("-ja")
            || lowered.hasSuffix("ja")
            || lowered.contains("japanese") {
            return .tdtJa
        }
        if lowered.contains("v3") {
            return .v3
        }
        if lowered.contains("v2") {
            return .v2
        }
        return .v2
    }

    /// Convenience: derive the exact repo directory from a catalog model name.
    public nonisolated static func modelDirectory(
        forName name: String,
        fluidAudioModelsRoot: URL
    ) -> URL {
        if name == orukeetModelName {
            return fluidAudioModelsRoot.appendingPathComponent("orukeet-coreml-preview", isDirectory: true)
        }
        return modelDirectory(for: modelVersion(forName: name), fluidAudioModelsRoot: fluidAudioModelsRoot)
    }
}
