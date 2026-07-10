//
//  NemotronStreamingEngine.swift
//  Pindrop
//
//  Created on 2026-06-05.
//
//  Streaming engine backed by FluidAudio's NemotronStreamingAsrManager (NVIDIA Nemotron
//  Speech Streaming 0.6B, cache-aware FastConformer-TDT). Unlike the retired Parakeet
//  EOU 120M engine, Nemotron emits natively punctuated and capitalized text (~2-3.5%
//  WER on LibriSpeech test-clean vs ~8-9% for the EOU model).
//
//  Nemotron has no end-of-utterance token, so this engine never fires the
//  end-of-utterance callback — segmentation falls to StreamingRefinementCoordinator's
//  idle-commit timer and the stop-time drain, both of which operate independently of
//  EOU signals.
//

import AVFoundation
import CoreML
import FluidAudio
import Foundation

// An actor, not @MainActor: the underlying FluidAudio manager is already an actor,
// and per-buffer processing must run off the main thread or UI rendering starves it
// (live partials then arrive only as a burst at session stop).
public actor NemotronStreamingEngine: StreamingTranscriptionEngine {

    public enum EngineError: Error, LocalizedError {
        case modelNotFound(String)
        case modelNotLoaded
        case invalidState(String)
        case processingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "Streaming model not found at path: \(path)"
            case .modelNotLoaded:
                return "Streaming model is not loaded"
            case .invalidState(let message):
                return message
            case .processingFailed(let message):
                return "Streaming transcription failed: \(message)"
            }
        }
    }

    public private(set) var state: StreamingTranscriptionState = .unloaded

    private var manager: NemotronStreamingAsrManager?
    private var transcriptionCallback: StreamingTranscriptionCallback?
    /// Stored for protocol conformance; never invoked — Nemotron has no EOU token.
    private var endOfUtteranceCallback: EndOfUtteranceCallback?

    /// Chunk-size variant to use when loading the model. Changing this after load has no
    /// effect until the manager is unloaded and reloaded.
    public private(set) var chunkProfile: StreamingChunkProfile

    public init(chunkProfile: StreamingChunkProfile = .standard) {
        self.chunkProfile = chunkProfile
    }

    /// Update the chunk profile and, if a manager is already loaded under a different
    /// profile, unload it so the next `loadModel(name:)` picks the new variant.
    public func updateChunkProfile(_ newProfile: StreamingChunkProfile) async {
        guard newProfile != chunkProfile else { return }
        chunkProfile = newProfile
        if manager != nil {
            await unloadModel()
        }
    }

    public func loadModel(name: String) async throws {
        guard state != .loading else { return }

        state = .loading

        do {
            let modelDirectory = resolveModelDirectory(for: name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw EngineError.modelNotFound(modelDirectory.path)
            }

            // Keep inference off the GPU (CPU+ANE only): CoreML's default `.all`
            // dispatches to the same GPU that composites the floating indicator's
            // blur/shader animations, and the two visibly contend at session start.
            // FluidAudio's own batch Parakeet path makes the same choice.
            let mlConfiguration = MLModelConfiguration()
            mlConfiguration.computeUnits = .cpuAndNeuralEngine
            let streamingManager = NemotronStreamingAsrManager(
                configuration: mlConfiguration,
                requestedChunkSize: chunkProfile.nemotronChunkSize
            )
            await streamingManager.setPartialCallback { [weak self] text in
                Task { [weak self] in
                    await self?.deliverPartial(text)
                }
            }

            try await streamingManager.loadModels(modelDir: modelDirectory)

            // CoreML specializes kernels lazily on the first prediction, not at
            // load — without this, that one-time spike lands on the first real
            // audio chunk of a session, mid pop-out animation. Push one silent
            // chunk (1.2s covers both chunk profiles) through the full
            // preprocessor→encoder→decoder→joint path while still `.loading`.
            let warmupSamples = [Float](repeating: 0, count: 19_200)
            if let warmupBuffer = try? makePCMBuffer(from: warmupSamples) {
                _ = try? await streamingManager.process(audioBuffer: warmupBuffer)
            }
            await streamingManager.reset()

            manager = streamingManager
            state = .ready
        } catch {
            state = .error
            if let engineError = error as? EngineError {
                throw engineError
            }
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        if let manager {
            await manager.reset()
        }
        manager = nil
        state = .unloaded
    }

    public func startStreaming() async throws {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        switch state {
        case .ready, .paused:
            await manager.reset()
            state = .streaming
        case .streaming:
            return
        case .loading, .unloaded, .error:
            throw EngineError.invalidState("Cannot start streaming while in state: \(state)")
        }
    }

    public func stopStreaming() async throws -> String {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        guard state == .streaming || state == .paused else {
            throw EngineError.invalidState("Cannot stop streaming while in state: \(state)")
        }

        do {
            let finalText = try await manager.finish()
            state = .ready
            return finalText
        } catch {
            state = .ready
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func pauseStreaming() async {
        guard state == .streaming else { return }
        state = .paused
    }

    public func resumeStreaming() async throws {
        guard state == .paused else {
            throw EngineError.invalidState("Cannot resume streaming while in state: \(state)")
        }
        state = .streaming
    }

    public func processAudioChunk(_ samples: [Float]) async throws {
        let buffer = try makePCMBuffer(from: samples)
        try await processAudioBuffer(buffer)
    }

    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        guard state == .streaming else {
            throw EngineError.invalidState("Cannot process audio while in state: \(state)")
        }

        do {
            _ = try await manager.process(audioBuffer: buffer)
        } catch {
            throw EngineError.processingFailed(error.localizedDescription)
        }
    }

    public func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) {
        transcriptionCallback = callback
    }

    public func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) {
        endOfUtteranceCallback = callback
    }

    /// Runs on the engine actor; consumers hop to their own isolation inside the
    /// callback (the session controller wraps delivery in a MainActor task).
    private func deliverPartial(_ text: String) {
        let result = StreamingTranscriptionResult(
            text: text,
            isFinal: false,
            timestamp: Date().timeIntervalSince1970
        )
        transcriptionCallback?(result)
    }

    public func reset() async {
        if let manager {
            await manager.reset()
            state = .ready
        } else {
            state = .unloaded
        }
    }

    private func resolveModelDirectory(for name: String) -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }

        let relativePath = trimmed.isEmpty ? chunkProfile.repoFolderName : trimmed
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
    }

    private func makePCMBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            throw EngineError.processingFailed("Failed to create PCM buffer")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        channelData.update(from: samples, count: samples.count)
        return buffer
    }
}
