//
//  VoiceActivityDetector.swift
//  PindropSpeech
//
//  Created on 2026-01-30.
//  Extracted to PindropSpeech on 2026-07-22.
//
//  Core owns VoiceActivityResult / VoiceSegment / VoiceActivityDetectorState and
//  the VoiceActivityDetector protocol. This file provides the FluidAudio Silero
//  adapter. The caller must pass the exact silero-vad repository directory
//  derived from ModelStorageLocations.fluidAudioModelsRoot; no Application Support
//  reconstruction and no VadManager default directory.
//

import CoreML
import FluidAudio
import Foundation
import PindropCore

/// FluidAudio Silero VAD adapter backed by an injected repository directory.
@MainActor
public final class FluidVoiceActivityDetector: VoiceActivityDetector {

    public enum DetectorError: Error, LocalizedError {
        case modelNotFound(String)
        case modelNotLoaded
        case invalidSampleRate(Int)
        case processingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let path):
                return "VAD model not found at path: \(path)"
            case .modelNotLoaded:
                return "VAD model is not loaded."
            case .invalidSampleRate(let sampleRate):
                return "Invalid sample rate: \(sampleRate). Expected \(VadManager.sampleRate)."
            case .processingFailed(let message):
                return "Voice activity detection failed: \(message)"
            }
        }
    }

    /// Exact Silero VAD repository directory (…/FluidAudio/Models/silero-vad).
    public let modelsDirectory: URL

    public private(set) var state: VoiceActivityDetectorState = .unloaded

    private var manager: VadManager?

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public func loadModel() async throws {
        if state == .loading || state == .ready {
            return
        }

        state = .loading

        do {
            let modelURL = modelsDirectory.appendingPathComponent(
                ModelNames.VAD.sileroVadFile,
                isDirectory: true
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                state = .error
                throw DetectorError.modelNotFound(modelURL.path)
            }

            let configuration = MLModelConfiguration()
            configuration.computeUnits = VadConfig.default.computeUnits
            configuration.allowLowPrecisionAccumulationOnGPU = true

            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            manager = VadManager(config: .default, vadModel: model)
            state = .ready
            Log.transcription.info("VAD model loaded from \(self.modelsDirectory.path)")
        } catch is CancellationError {
            state = .unloaded
            manager = nil
            throw CancellationError()
        } catch let error as DetectorError {
            state = .error
            manager = nil
            throw error
        } catch {
            state = .error
            manager = nil
            throw DetectorError.processingFailed(error.localizedDescription)
        }
    }

    public func unloadModel() async {
        manager = nil
        state = .unloaded
        Log.transcription.debug("VAD model unloaded")
    }

    public func detectVoiceActivity(
        in samples: [Float],
        sampleRate: Int
    ) async throws -> [VoiceActivityResult] {
        let manager = try await requireManager()
        try validateSampleRate(sampleRate)

        state = .processing
        defer { state = .ready }

        do {
            let results = try await manager.process(samples)
            let chunkDuration = Double(VadManager.chunkSize) / Double(VadManager.sampleRate)
            return results.enumerated().compactMap { index, result in
                guard result.isVoiceActive else { return nil }
                let startTime = Double(index) * chunkDuration
                return VoiceActivityResult(
                    startTime: startTime,
                    endTime: startTime + chunkDuration,
                    probability: result.probability
                )
            }
        } catch {
            state = .error
            throw DetectorError.processingFailed(error.localizedDescription)
        }
    }

    public func segmentSpeech(
        in samples: [Float],
        sampleRate: Int
    ) async throws -> [VoiceSegment] {
        let manager = try await requireManager()
        try validateSampleRate(sampleRate)

        state = .processing
        defer { state = .ready }

        do {
            let segments = try await manager.segmentSpeech(samples, config: .default)
            return segments.compactMap { segment in
                let startSample = max(0, segment.startSample(sampleRate: sampleRate))
                let endSample = min(samples.count, segment.endSample(sampleRate: sampleRate))
                guard endSample > startSample else { return nil }
                return VoiceSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    samples: Array(samples[startSample..<endSample])
                )
            }
        } catch {
            state = .error
            throw DetectorError.processingFailed(error.localizedDescription)
        }
    }

    private func requireManager() async throws -> VadManager {
        if let manager {
            return manager
        }
        if state == .unloaded || state == .error {
            try await loadModel()
        }
        guard let manager else {
            throw DetectorError.modelNotLoaded
        }
        return manager
    }

    private func validateSampleRate(_ sampleRate: Int) throws {
        guard sampleRate == VadManager.sampleRate else {
            throw DetectorError.invalidSampleRate(sampleRate)
        }
    }
}
