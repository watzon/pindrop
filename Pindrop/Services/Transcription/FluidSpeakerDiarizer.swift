//
//  FluidSpeakerDiarizer.swift
//  Pindrop
//
//  Created on 2026-03-02.
//

import Foundation
import FluidAudio

@MainActor
public final class FluidSpeakerDiarizer: SpeakerDiarizer {

    public enum DiarizerServiceError: Error, LocalizedError {
        case invalidSampleRate(Int)
        case invalidAudioSamples
        case modelNotLoaded
        case modelLoadFailed(String)
        case processingFailed(String)
        case speakerEmbeddingUnavailable
        case invalidKnownSpeaker(String)
        case comparisonFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSampleRate(let sampleRate):
                return "Invalid sample rate: \(sampleRate). Expected a positive value."
            case .invalidAudioSamples:
                return "Invalid audio samples provided for diarization."
            case .modelNotLoaded:
                return "Diarization model is not loaded."
            case .modelLoadFailed(let message):
                return "Failed to load diarization model: \(message)"
            case .processingFailed(let message):
                return "Speaker diarization failed: \(message)"
            case .speakerEmbeddingUnavailable:
                return "Unable to compute speaker embedding for comparison."
            case .invalidKnownSpeaker(let message):
                return "Invalid known speaker: \(message)"
            case .comparisonFailed(let message):
                return "Failed to compare speakers: \(message)"
            }
        }
    }

    public private(set) var state: SpeakerDiarizerState = .unloaded
    public let mode: DiarizationMode = .offline

    private let worker: FluidSpeakerDiarizerWorker
    private var knownSpeakersByID: [String: Speaker] = [:]

    public init(config: DiarizerConfig = .default) {
        self.worker = FluidSpeakerDiarizerWorker(config: config)
    }

    public func loadModels() async throws {
        if state == .loading || state == .ready {
            return
        }

        state = .loading

        do {
            try await worker.loadModels()
            state = .ready
            Log.transcription.info("Speaker diarization model loaded")
        } catch {
            state = .error
            let mappedError = mapError(error)
            Log.transcription.error("Speaker diarization model load failed: \(mappedError)")
            throw mappedError
        }
    }

    public func unloadModels() async {
        await worker.unloadModels()
        state = .unloaded
        Log.transcription.debug("Speaker diarization model unloaded")
    }

    public func diarize(samples: [Float], sampleRate: Int) async throws -> DiarizationResult {
        guard sampleRate > 0 else {
            throw DiarizerServiceError.invalidSampleRate(sampleRate)
        }

        guard !samples.isEmpty else {
            throw DiarizerServiceError.invalidAudioSamples
        }

        if state == .unloaded || state == .error {
            try await loadModels()
        }

        guard state == .ready else {
            throw DiarizerServiceError.modelNotLoaded
        }

        state = .processing

        do {
            let mappedSegments = try await worker.diarize(samples: samples, sampleRate: sampleRate)
            var speakersByID: [String: Speaker] = [:]
            for segment in mappedSegments {
                speakersByID[segment.speaker.id] = segment.speaker
            }
            let audioDuration = TimeInterval(samples.count) / TimeInterval(sampleRate)
            let mapped = DiarizationResult(
                segments: mappedSegments,
                speakers: speakersByID.values.sorted { $0.label < $1.label },
                audioDuration: audioDuration
            )
            state = .ready
            return mapped
        } catch {
            state = .error
            let mappedError = mapError(error)
            Log.transcription.error("Speaker diarization failed: \(mappedError)")
            throw mappedError
        }
    }

    public func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        do {
            let first = try await diarize(samples: audio1, sampleRate: 16000)
            let second = try await diarize(samples: audio2, sampleRate: 16000)

            guard let firstEmbedding = representativeEmbedding(from: first),
                  let secondEmbedding = representativeEmbedding(from: second) else {
                throw DiarizerServiceError.speakerEmbeddingUnavailable
            }

            let distance = SpeakerUtilities.cosineDistance(firstEmbedding, secondEmbedding)
            guard distance.isFinite else {
                throw DiarizerServiceError.comparisonFailed("Invalid similarity distance")
            }

            let similarity = max(0.0, min(1.0, 1.0 - distance))
            return similarity
        } catch {
            throw mapError(error)
        }
    }

    public func registerKnownSpeaker(_ speaker: Speaker) async throws {
        guard let embedding = speaker.embedding, !embedding.isEmpty else {
            throw DiarizerServiceError.invalidKnownSpeaker("Missing speaker embedding")
        }

        let normalizedSpeaker = Speaker(id: speaker.id, label: speaker.label, embedding: embedding)
        knownSpeakersByID[normalizedSpeaker.id] = normalizedSpeaker

        do {
            try await worker.registerKnownSpeaker(normalizedSpeaker)
        } catch {
            throw mapError(error)
        }
    }

    public func clearKnownSpeakers() async {
        knownSpeakersByID.removeAll()
        await worker.clearKnownSpeakers()
    }

    private func representativeEmbedding(from result: DiarizationResult) -> [Float]? {
        result.segments
            .sorted { $0.duration > $1.duration }
            .compactMap(\.speaker.embedding)
            .first
    }

    private func mapError(_ error: Error) -> DiarizerServiceError {
        if let serviceError = error as? DiarizerServiceError {
            return serviceError
        }

        if let diarizerError = error as? DiarizerError {
            switch diarizerError {
            case .notInitialized:
                return .modelNotLoaded
            case .modelDownloadFailed, .modelCompilationFailed:
                return .modelLoadFailed(diarizerError.localizedDescription)
            case .processingFailed(let message):
                return .processingFailed(message)
            case .invalidAudioData:
                return .invalidAudioSamples
            case .embeddingExtractionFailed:
                return .processingFailed("Embedding extraction failed")
            case .memoryAllocationFailed:
                return .processingFailed("Memory allocation failed")
            case .invalidArrayBounds:
                return .processingFailed("Invalid array bounds")
            }
        }

        return .processingFailed(error.localizedDescription)
    }
}

private final class FluidSpeakerDiarizerWorker {
    private let queue = DispatchQueue(label: "tech.watzon.pindrop.transcription.diarizer")
    private let config: DiarizerConfig

    private var diarizerManager: DiarizerManager?
    private var knownSpeakersByID: [String: Speaker] = [:]

    init(config: DiarizerConfig) {
        self.config = config
    }

    func loadModels() async throws {
        let models = try await DiarizerModels.load(from: DiarizerModels.defaultModelsDirectory())
        let knownSpeakers = Array(knownSpeakersByID.values)

        try await run {
            let manager = DiarizerManager(config: self.config)
            manager.initialize(models: models)

            if !knownSpeakers.isEmpty {
                try manager.initializeKnownSpeakers(
                    knownSpeakers.map { speaker in
                        guard let embedding = speaker.embedding, !embedding.isEmpty else {
                            throw FluidSpeakerDiarizer.DiarizerServiceError.invalidKnownSpeaker("Missing speaker embedding")
                        }

                        return .init(
                            id: speaker.id,
                            name: speaker.label,
                            currentEmbedding: embedding,
                            duration: 0,
                            isPermanent: true
                        )
                    }
                )
            }

            self.diarizerManager = manager
        }
    }

    func unloadModels() async {
        await runWithoutThrowing {
            self.diarizerManager?.cleanup()
            self.diarizerManager = nil
        }
    }

    func diarize(samples: [Float], sampleRate: Int) async throws -> [SpeakerSegment] {
        try await run {
            guard let diarizerManager = self.diarizerManager else {
                throw FluidSpeakerDiarizer.DiarizerServiceError.modelNotLoaded
            }
            let rawResult = try diarizerManager.performCompleteDiarization(samples, sampleRate: sampleRate)
            let sortedSegments = rawResult.segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

            return sortedSegments.enumerated().compactMap { index, segment in
                let fallbackSpeakerID = "speaker-\(index + 1)"
                let speakerID = segment.speakerId.isEmpty ? fallbackSpeakerID : segment.speakerId
                let knownSpeaker = self.knownSpeakersByID[speakerID]
                let embedding = segment.embedding.isEmpty ? knownSpeaker?.embedding : segment.embedding
                let label = knownSpeaker?.label ?? speakerID

                let startTime = TimeInterval(segment.startTimeSeconds)
                let endTime = TimeInterval(segment.endTimeSeconds)
                guard endTime > startTime else { return nil }

                let confidence = min(max(segment.qualityScore, 0.0), 1.0)
                return SpeakerSegment(
                    speaker: Speaker(id: speakerID, label: label, embedding: embedding),
                    startTime: startTime,
                    endTime: endTime,
                    confidence: confidence
                )
            }
        }
    }

    func registerKnownSpeaker(_ speaker: Speaker) async throws {
        try await run {
            guard let embedding = speaker.embedding, !embedding.isEmpty else {
                throw FluidSpeakerDiarizer.DiarizerServiceError.invalidKnownSpeaker("Missing speaker embedding")
            }

            self.knownSpeakersByID[speaker.id] = speaker
            guard let diarizerManager = self.diarizerManager else { return }
            diarizerManager.initializeKnownSpeakers([
                .init(
                    id: speaker.id,
                    name: speaker.label,
                    currentEmbedding: embedding,
                    duration: 0,
                    isPermanent: true
                )
            ])
        }
    }

    func clearKnownSpeakers() async {
        await runWithoutThrowing {
            self.knownSpeakersByID.removeAll()
            self.diarizerManager?.speakerManager.reset(keepIfPermanent: false)
        }
    }

    private func run<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runWithoutThrowing(_ operation: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                operation()
                continuation.resume()
            }
        }
    }
}
