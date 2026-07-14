//
//  NemotronStreamingEngine.swift
//  Pindrop
//
//  Created on 2026-06-05.
//
//  Streaming engine backed by FluidAudio's StreamingNemotronAsrManager (NVIDIA Nemotron
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

    private var manager: StreamingNemotronAsrManager?
    private var transcriptionCallback: StreamingTranscriptionCallback?
    /// Stored for protocol conformance; never invoked — Nemotron has no EOU token.
    private var endOfUtteranceCallback: EndOfUtteranceCallback?
    /// Every manager callback closes over the session that installed it. Reset
    /// advances this value before awaiting the manager barrier, so callback Tasks
    /// already queued on the cooperative executor reject themselves when resumed.
    private var callbackSessionGeneration: UInt64 = 1

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
            let streamingManager = StreamingNemotronAsrManager(
                configuration: mlConfiguration,
                requestedChunkSize: chunkProfile.nemotronChunkSize
            )

            do {
                try await streamingManager.loadModels(from: modelDirectory)
            } catch {
                // The fused decoder_joint.mlmodelc is OPTIONAL — FluidAudio only loads
                // it when the file exists — but a stale/corrupt copy (early exports
                // shipped one that fails with "Error in reading the MIL network", and
                // the cached-download check never re-validates it) throws and bricks
                // streaming entirely. Quarantine it and retry once without the fused
                // path; restore it if the retry proves it wasn't the culprit.
                let fusedURL = modelDirectory.appendingPathComponent("decoder_joint.mlmodelc")
                guard FileManager.default.fileExists(atPath: fusedURL.path) else {
                    throw error
                }
                let quarantineURL = modelDirectory.appendingPathComponent("decoder_joint.mlmodelc.broken")
                try? FileManager.default.removeItem(at: quarantineURL)
                try FileManager.default.moveItem(at: fusedURL, to: quarantineURL)
                Log.transcription.warning(
                    "Streaming model load failed (\(error.localizedDescription)); quarantined optional decoder_joint.mlmodelc and retrying without the fused path"
                )
                do {
                    try await streamingManager.loadModels(from: modelDirectory)
                } catch let retryError {
                    try? FileManager.default.moveItem(at: quarantineURL, to: fusedURL)
                    throw retryError
                }
            }

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
        callbackSessionGeneration &+= 1
        let manager = manager
        self.manager = nil
        state = .unloaded
        if let manager {
            await manager.reset()
        }
    }

    public func startStreaming() async throws {
        guard let manager else {
            throw EngineError.modelNotLoaded
        }

        switch state {
        case .ready, .paused:
            callbackSessionGeneration &+= 1
            let generation = callbackSessionGeneration
            await manager.reset()
            guard self.manager === manager,
                  callbackSessionGeneration == generation else {
                throw CancellationError()
            }

            // Capture both callback and generation for this session. A callback
            // queued before reset retains the old generation and cannot be
            // reclassified as belonging to a subsequent start.
            let callback = transcriptionCallback
            await manager.setPartialCallback { [weak self, callback] text in
                Task { [weak self, callback] in
                    await self?.deliverPartial(
                        text,
                        generation: generation,
                        callback: callback
                    )
                }
            }
            guard self.manager === manager,
                  callbackSessionGeneration == generation else {
                throw CancellationError()
            }
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
    private func deliverPartial(
        _ text: String,
        generation: UInt64,
        callback: StreamingTranscriptionCallback?
    ) {
        guard generation == callbackSessionGeneration else { return }
        let result = StreamingTranscriptionResult(
            text: text,
            isFinal: false,
            timestamp: Date().timeIntervalSince1970
        )
        callback?(result)
    }

    public func reset() async {
        // Invalidate callback Tasks before the manager await. Actor reentrancy can
        // run those Tasks while reset is suspended, but their generation check
        // makes the barrier observable immediately and permanently.
        callbackSessionGeneration &+= 1
        let resetGeneration = callbackSessionGeneration
        guard let manager else {
            state = .unloaded
            return
        }
        await manager.reset()
        guard self.manager === manager,
              callbackSessionGeneration == resetGeneration else {
            return
        }
        state = .ready
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
