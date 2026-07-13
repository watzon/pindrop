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

    /// Fixed offline Community-1 clustering threshold selected by the diarization quality benchmark.
    public static let offlineClusteringThreshold: Double = 0.60

    nonisolated private static let requiredSampleRate = 16_000
    nonisolated private static let expectedEmbeddingDimension = 256
    nonisolated private static let validSpeakerCountRange = 1...20

    public enum DiarizerServiceError: Error, LocalizedError {
        case invalidSampleRate(Int)
        case invalidAudioSamples
        case modelNotLoaded
        case modelLoadFailed(String)
        case processingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSampleRate(let sampleRate):
                return "Invalid sample rate: \(sampleRate). Expected \(FluidSpeakerDiarizer.requiredSampleRate)."
            case .invalidAudioSamples:
                return "Invalid audio samples provided for diarization."
            case .modelNotLoaded:
                return "Diarization model is not loaded."
            case .modelLoadFailed(let message):
                return "Failed to load diarization model: \(message)"
            case .processingFailed(let message):
                return "Speaker diarization failed: \(message)"
            }
        }
    }

    public private(set) var state: SpeakerDiarizerState = .unloaded
    public let mode: DiarizationMode = .offline

    private let modelsCache = FluidSpeakerDiarizerModelsCache()

    public init() {}

    public func loadModels() async throws {
        if state == .loading || state == .ready {
            return
        }

        state = .loading

        do {
            try await modelsCache.loadModels()
            state = .ready
            Log.transcription.info("Speaker diarization model loaded (offline-community1)")
        } catch is CancellationError {
            state = .unloaded
            Log.transcription.info("Speaker diarization model load canceled")
            throw CancellationError()
        } catch {
            state = .error
            let mappedError = mapError(error)
            Log.transcription.error("Speaker diarization model load failed: \(mappedError)")
            throw mappedError
        }
    }

    public func unloadModels() async {
        await modelsCache.unloadModels()
        state = .unloaded
        Log.transcription.debug("Speaker diarization model unloaded")
    }

    public func diarize(
        samples: [Float],
        sampleRate: Int,
        options: DiarizationOptions
    ) async throws -> DiarizationResult {
        guard sampleRate == Self.requiredSampleRate else {
            throw DiarizerServiceError.invalidSampleRate(sampleRate)
        }

        guard !samples.isEmpty else {
            throw DiarizerServiceError.invalidAudioSamples
        }

        if let expectedSpeakerCount = options.expectedSpeakerCount,
           !Self.validSpeakerCountRange.contains(expectedSpeakerCount) {
            throw DiarizerServiceError.processingFailed(
                "Expected speaker count must be between 1 and 20."
            )
        }

        if state == .unloaded || state == .error {
            try await loadModels()
        }

        guard state == .ready else {
            throw DiarizerServiceError.modelNotLoaded
        }

        state = .processing
        let processingStarted = Date()
        let audioDuration = TimeInterval(samples.count) / TimeInterval(sampleRate)

        do {
            let models = try await modelsCache.requireModels()
            var config = OfflineDiarizerConfig.default
            config.clustering.threshold = Self.offlineClusteringThreshold
            if let expectedSpeakerCount = options.expectedSpeakerCount {
                config = config.withSpeakers(exactly: expectedSpeakerCount)
            }
            try config.validate()

            let manager = OfflineDiarizerManager(config: config)
            manager.initialize(models: models)

            let rawSegments: [TimedSpeakerSegment]
            let speakerDatabase: [String: [Float]]?
            do {
                let rawResult = try await manager.process(audio: samples)
                rawSegments = rawResult.segments
                speakerDatabase = rawResult.speakerDatabase
            } catch OfflineDiarizationError.noSpeechDetected {
                state = .ready
                let processingDuration = Date().timeIntervalSince(processingStarted)
                logPipelineDiagnostics(
                    requestedSpeakerCount: options.expectedSpeakerCount,
                    observedSpeakerCount: 0,
                    audioDuration: audioDuration,
                    processingDuration: processingDuration
                )
                return DiarizationResult(segments: [], speakers: [], audioDuration: audioDuration)
            }

            let mapped = mapResult(
                segments: rawSegments,
                speakerDatabase: speakerDatabase,
                audioDuration: audioDuration
            )
            state = .ready

            let processingDuration = Date().timeIntervalSince(processingStarted)
            logPipelineDiagnostics(
                requestedSpeakerCount: options.expectedSpeakerCount,
                observedSpeakerCount: mapped.speakerCount,
                audioDuration: audioDuration,
                processingDuration: processingDuration
            )
            return mapped
        } catch is CancellationError {
            state = .ready
            Log.transcription.info("Speaker diarization canceled")
            throw CancellationError()
        } catch {
            state = .error
            let mappedError = mapError(error)
            Log.transcription.error("Speaker diarization failed: \(mappedError)")
            throw mappedError
        }
    }

    private func mapResult(
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        audioDuration: TimeInterval
    ) -> DiarizationResult {
        let sortedSegments = segments.sorted {
            $0.startTimeSeconds < $1.startTimeSeconds
        }

        var speakersByID: [String: Speaker] = [:]
        var speakersInOrder: [Speaker] = []
        var mappedSegments: [SpeakerSegment] = []

        for (index, segment) in sortedSegments.enumerated() {
            let startTime = TimeInterval(segment.startTimeSeconds)
            let endTime = TimeInterval(segment.endTimeSeconds)
            guard endTime > startTime else { continue }

            let speakerID = segment.speakerId.isEmpty ? "speaker-\(index + 1)" : segment.speakerId
            let embedding = resolveEmbedding(
                segmentEmbedding: segment.embedding,
                speakerID: speakerID,
                speakerDatabase: speakerDatabase
            )
            let confidence = min(max(segment.qualityScore, 0.0), 1.0)

            let speaker: Speaker
            if let existing = speakersByID[speakerID] {
                speaker = existing
            } else {
                let label = "Speaker \(speakersInOrder.count + 1)"
                let created = Speaker(id: speakerID, label: label, embedding: embedding)
                speakersByID[speakerID] = created
                speakersInOrder.append(created)
                speaker = created
            }

            mappedSegments.append(
                SpeakerSegment(
                    speaker: speaker,
                    startTime: startTime,
                    endTime: endTime,
                    confidence: confidence
                )
            )
        }

        return DiarizationResult(
            segments: mappedSegments,
            speakers: speakersInOrder,
            audioDuration: audioDuration
        )
    }

    private func resolveEmbedding(
        segmentEmbedding: [Float],
        speakerID: String,
        speakerDatabase: [String: [Float]]?
    ) -> [Float]? {
        if !segmentEmbedding.isEmpty,
           segmentEmbedding.count == Self.expectedEmbeddingDimension {
            return segmentEmbedding
        }
        if let databaseEmbedding = speakerDatabase?[speakerID], !databaseEmbedding.isEmpty {
            return databaseEmbedding
        }
        return nil
    }

    private func logPipelineDiagnostics(
        requestedSpeakerCount: Int?,
        observedSpeakerCount: Int,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        let requested = requestedSpeakerCount.map(String.init) ?? "automatic"
        let audioText = String(format: "%.3f", audioDuration)
        let processingText = String(format: "%.3f", processingDuration)
        let thresholdText = String(format: "%.2f", Self.offlineClusteringThreshold)
        Log.transcription.info(
            "Speaker diarization pipeline=offline-community1 requestedSpeakers=\(requested) observedSpeakers=\(observedSpeakerCount) audioDuration=\(audioText)s processingDuration=\(processingText)s clusteringThreshold=\(thresholdText)"
        )
    }

    private func mapError(_ error: Error) -> DiarizerServiceError {
        if let serviceError = error as? DiarizerServiceError {
            return serviceError
        }

        if let offlineError = error as? OfflineDiarizationError {
            switch offlineError {
            case .modelNotLoaded:
                return .modelLoadFailed(offlineError.localizedDescription)
            case .invalidConfiguration, .invalidBatchSize, .processingFailed, .exportFailed:
                return .processingFailed(offlineError.localizedDescription)
            case .noSpeechDetected:
                // noSpeechDetected is handled as an empty success at the call site.
                return .processingFailed(offlineError.localizedDescription)
            }
        }

        return .processingFailed(error.localizedDescription)
    }
}

/// Caches compiled offline diarization models. Each diarization call still builds a
/// call-local `OfflineDiarizerManager` so speaker-count constraints never leak across jobs.
private actor FluidSpeakerDiarizerModelsCache {
    private var models: OfflineDiarizerModels?

    func loadModels() async throws {
        if models != nil {
            return
        }

        let loaded = try await OfflineDiarizerModels.load(
            from: OfflineDiarizerModels.defaultModelsDirectory()
        )
        if models == nil {
            models = loaded
        }
    }

    func unloadModels() {
        models = nil
    }

    func requireModels() throws -> OfflineDiarizerModels {
        guard let models else {
            throw FluidSpeakerDiarizer.DiarizerServiceError.modelNotLoaded
        }
        return models
    }
}
