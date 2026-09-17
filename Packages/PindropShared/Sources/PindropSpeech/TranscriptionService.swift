//
//  TranscriptionService.swift
//  PindropSpeech
//
//  Created on 2026-01-25.
//

import AVFoundation
import CryptoKit
import Foundation
import FluidAudio
import PindropCore
import os.log
/// The provider and model that the service has actually prepared for streaming.
///
/// This is deliberately the effective engine identity, rather than the requested
/// settings: Apple SpeechTranscriber can fall back to Parakeet at runtime.
public struct StreamingEngineIdentity: Sendable, Equatable {
    public let providerIdentifier: String
    public let modelIdentifier: String

    public init(providerIdentifier: String, modelIdentifier: String) {
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
    }
}


public struct TranscriptionChunkInput: Sendable, Equatable {
    public let chunkID: UUID
    public let sequence: Int
    public let startOffset: TimeInterval
    public let duration: TimeInterval
    public let fileURL: URL
    public let byteCount: Int
    public let sha256: String

    public init(
        chunkID: UUID,
        sequence: Int,
        startOffset: TimeInterval,
        duration: TimeInterval,
        fileURL: URL,
        byteCount: Int,
        sha256: String
    ) {
        self.chunkID = chunkID
        self.sequence = sequence
        self.startOffset = startOffset
        self.duration = duration
        self.fileURL = fileURL
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct TranscriptionChunkOutput: Sendable, Equatable {
    public let chunkID: UUID
    public let sequence: Int
    public let startOffset: TimeInterval
    public let duration: TimeInterval
    public let plainText: String
    public let diarizedSegments: [DiarizedTranscriptSegment]?
    public let diarizationWarning: String?

    public init(
        chunkID: UUID,
        sequence: Int,
        startOffset: TimeInterval,
        duration: TimeInterval,
        plainText: String,
        diarizedSegments: [DiarizedTranscriptSegment]? = nil,
        diarizationWarning: String? = nil
    ) {
        self.chunkID = chunkID
        self.sequence = sequence
        self.startOffset = startOffset
        self.duration = duration
        self.plainText = plainText
        self.diarizedSegments = diarizedSegments
        self.diarizationWarning = diarizationWarning
    }
}

public enum DiarizationFailurePolicy: Sendable, Equatable {
    case bestEffort
    case required
}

@MainActor
@Observable
public final class TranscriptionService {

    public enum State: Equatable {
        case unloaded
        case loading
        case ready
        case transcribing
        case error
    }

    public enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case invalidMeetingChunk(String)
        case duplicateMeetingChunkSequence(Int)
        case overlappingMeetingChunk(sequence: Int)
        case nonContiguousMeetingChunk(expected: TimeInterval, actual: TimeInterval, sequence: Int)
        case invalidMeetingChunkSegmentBounds(sequence: Int)
        case transcriptionFailed(String)
        case modelLoadFailed(String)
        case diarizationFailed(String)
        case engineSwitchDuringTranscription
        case streamingModelNotAvailable(String)
        case streamingNotReady
        case streamingStartFailed(String)
        case streamingProcessingFailed(String)
        case streamingStopFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM format."
            case .invalidMeetingChunk(let message):
                return "Invalid meeting audio chunk: \(message)"
            case .duplicateMeetingChunkSequence(let sequence):
                return "Meeting transcript contains duplicate chunk sequence \(sequence)."
            case .overlappingMeetingChunk(let sequence):
                return "Meeting transcript chunk \(sequence) overlaps the preceding chunk."
            case .nonContiguousMeetingChunk(let expected, let actual, let sequence):
                return "Meeting transcript chunk \(sequence) starts at \(actual), expected \(expected)."
            case .invalidMeetingChunkSegmentBounds(let sequence):
                return "Meeting transcript chunk \(sequence) contains an out-of-bounds diarized segment."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
            case .diarizationFailed(let message):
                return "Diarization failed: \(message)"
            case .engineSwitchDuringTranscription:
                return "Cannot switch engines during active transcription"
            case .streamingModelNotAvailable(let path):
                return "Streaming model not available at path: \(path)"
            case .streamingNotReady:
                return "Streaming engine not ready. Call prepareStreamingEngine() first."
            case .streamingStartFailed(let message):
                return "Failed to start streaming transcription: \(message)"
            case .streamingProcessingFailed(let message):
                return "Failed to process streaming audio: \(message)"
            case .streamingStopFailed(let message):
                return "Failed to stop streaming transcription: \(message)"
            }
        }
    }

    private static let sampleRate = 16_000
    private static let bytesPerFloatSample = MemoryLayout<Float>.size
    private static let maximumMeetingChunkByteCount = 19_200_000
    private static let meetingChunkOffsetTolerance = 1.0 / 16_000.0
    private static let meetingChunkReadSize = 64 * 1024
    private static let diarizationMergeGapSeconds: TimeInterval = 0.30
    private static let segmentContextPaddingSeconds: TimeInterval = 0.150
    private static let identityEligibleSegmentDurationSeconds: TimeInterval = 1.0
    private static let identityEligibleSegmentConfidence: Float = 0.45
    private static let identityLongSegmentDurationSeconds: TimeInterval = 5.0
    private static let identityConsensusWeightRatio: Float = 0.70
    private static let offlineCommunity1ClusteringThreshold: Float = 0.60
    private static let maximumTranscriptChunkDurationSeconds: TimeInterval = 12.0
    private static let maximumTranscriptChunkWordCount = 28
    private static let targetTranscriptChunkWordCount = 20
    public nonisolated static let defaultDiarizationTimeoutSeconds: TimeInterval = 300
    public nonisolated static let defaultModelLoadTimeoutSeconds: TimeInterval? = nil

    public private(set) var state: State = .unloaded
    public private(set) var error: Error?
    private var engine: (any TranscriptionEngine)?
    private var speakerDiarizer: (any SpeakerDiarizer)?
    private var voiceActivityDetector: (any VoiceActivityDetector)?
    private var streamingEngine: (any StreamingTranscriptionEngine)?

    /// The live engine for the streaming session's audio pump. The pump runs on a
    /// detached task and calls the engine directly — routing each buffer through
    /// this @MainActor service would re-serialize decode behind UI work.
    public var activeStreamingEngine: (any StreamingTranscriptionEngine)? { streamingEngine }
    /// The provider/model pair of `activeStreamingEngine`, after backend fallback
    /// and Parakeet profile selection have been resolved.
    public private(set) var activeStreamingEngineIdentity: StreamingEngineIdentity?

    /// In-flight streaming-engine preparation, shared by concurrent callers so a
    /// session starting during the launch prewarm awaits the same load instead of
    /// hitting the engine's `.loading` state and falling back to batch. Class
    /// wrapper so callers can identity-check before clearing the slot.
    private final class StreamingPrepareHandle {
        let epoch: UInt64
        let task: Task<Void, Error>

        init(epoch: UInt64, task: Task<Void, Error>) {
            self.epoch = epoch
            self.task = task
        }
    }
    /// A reset is a session barrier. Callers arriving while it is active wait for
    /// completion rather than reactivating the engine's invariant callback bridge.
    private final class StreamingResetHandle {
        let epoch: UInt64
        let engineID: ObjectIdentifier
        private var isFinished = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(epoch: UInt64, engine: any StreamingTranscriptionEngine) {
            self.epoch = epoch
            self.engineID = ObjectIdentifier(engine)
        }

        func wait() async {
            guard !isFinished else { return }
            await withCheckedContinuation { continuation in
                if isFinished {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }

        func finish() {
            guard !isFinished else { return }
            isFinished = true
            let waiters = waiters
            self.waiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    private final class StreamingEngineLease {
        let engine: any StreamingTranscriptionEngine
        let identity: ObjectIdentifier
        let epoch: UInt64
        var isReleased = false

        init(engine: any StreamingTranscriptionEngine, epoch: UInt64) {
            self.engine = engine
            self.identity = ObjectIdentifier(engine)
            self.epoch = epoch
        }
    }

    private final class StreamingCallbackBridge {
        weak var engine: AnyObject?
        let source: StreamingCallbackDelivery.Source

        init(engine: any StreamingTranscriptionEngine, source: StreamingCallbackDelivery.Source) {
            self.engine = engine as AnyObject
            self.source = source
        }
    }

    private var streamingResetHandle: StreamingResetHandle?
    private var streamingEngineLeaseCounts: [ObjectIdentifier: Int] = [:]
    private var streamingEngineLeaseDrainWaiters:
        [ObjectIdentifier: [CheckedContinuation<Void, Never>]] = [:]
    private var streamingEngineAvailabilityWaiters:
        [ObjectIdentifier: [CheckedContinuation<Void, Never>]] = [:]
    private var retiredStreamingEngineIdentities: Set<ObjectIdentifier> = []
    private var streamingRetirementCleanupCounts: [ObjectIdentifier: Int] = [:]
    private var streamingCallbackBridges: [ObjectIdentifier: StreamingCallbackBridge] = [:]
    private var streamingLifecycleEpoch: UInt64 = 1
    private var streamingPrepareHandle: StreamingPrepareHandle?
    private var streamingCallbackSource: StreamingCallbackDelivery.Source?
    private var currentProvider: ModelManager.ModelProvider?
    private enum BatchModelIdentity: Equatable {
        case named(modelName: String, provider: ModelManager.ModelProvider)
        case path(String)
    }
    /// Last successfully loaded batch model. This survives hard-timeout
    /// invalidation so the next batch request can create a fresh engine.
    private var batchModelIdentity: BatchModelIdentity?
    private final class BatchLoadHandle {
        let identity: BatchModelIdentity
        let task: Task<Void, Error>
        init(identity: BatchModelIdentity, task: Task<Void, Error>) {
            self.identity = identity
            self.task = task
        }
    }
    private var batchLoadHandle: BatchLoadHandle?
    /// Identifies the only operation permitted to update batch-transcription
    /// state. A timed-out noncooperative engine keeps its own captured instance,
    /// while this service drops that instance before allowing a newly loaded one.
    private var activeTranscriptionGeneration: UInt64?
    private var nextTranscriptionGeneration: UInt64 = 1
    private var streamingPartialCallback: StreamingEmissionSink?
    private var streamingFinalUtteranceCallback: StreamingEmissionSink?
    /// Engine emissions hop once onto the main actor through this bridge. Partials
    /// coalesce to the latest value; finals stay ordered and lossless. Coalescing
    /// drops intermediate partials, never the fed watermark of the survivor: the
    /// watermark travels inside the emission it belongs to.
    private let streamingCallbackDelivery = StreamingCallbackDelivery()

    private let engineFactory: @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    private let openAIAPIKeyProvider: @MainActor () throws -> String
    private let speakerDiarizerFactory: @MainActor (_ modelsDirectory: URL) -> any SpeakerDiarizer
    private let voiceActivityDetectorFactory: @MainActor (_ modelsDirectory: URL) -> any VoiceActivityDetector
    private let streamingEngineFactory: @MainActor (_ profile: StreamingChunkProfile, _ modelsRoot: URL) -> any StreamingTranscriptionEngine
    private let appleSpeechEngineFactory: @MainActor () -> (any StreamingTranscriptionEngine)?
    private var streamingChunkProfileProvider: @MainActor () -> StreamingChunkProfile
    private var streamingBackendProvider: @MainActor () -> TranscriptionBackend
    private let speakerIdentityService: (any SpeakerIdentityMatching)?
    private let storageLocations: ModelStorageLocations
    private let audioPreprocessor: any AudioPreprocessing
    private let diarizationTimeoutSeconds: TimeInterval?
    /// Production loads can legitimately take several minutes while Core ML
    /// specializes a model. A deadline is therefore test-only and opt-in.
    private let modelLoadTimeoutSeconds: TimeInterval?

    /// True once this service substituted Parakeet for a requested Apple backend.
    /// `StreamingSessionController` surfaces one generic-session toast and consumes
    /// artifact-session fallback silently.
    public private(set) var appleBackendFellBackToParakeet: Bool = false

    public init(
        storageLocations: ModelStorageLocations,
        engineFactory: (@MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine)? = nil,
        openAIAPIKeyProvider: @escaping @MainActor () throws -> String = {
            throw OpenAITranscriptionEngine.EngineError.apiKeyMissing
        },
        diarizerFactory: (@MainActor (_ modelsDirectory: URL) -> any SpeakerDiarizer)? = nil,
        voiceActivityDetectorFactory: (@MainActor (_ modelsDirectory: URL) -> any VoiceActivityDetector)? = nil,
        streamingEngineFactory: (@MainActor (_ profile: StreamingChunkProfile, _ modelsRoot: URL) -> any StreamingTranscriptionEngine)? = nil,
        appleSpeechEngineFactory: (@MainActor () -> (any StreamingTranscriptionEngine)?)? = nil,
        streamingChunkProfileProvider: @escaping @MainActor () -> StreamingChunkProfile = { .standard },
        streamingBackendProvider: @escaping @MainActor () -> TranscriptionBackend = { .parakeet },
        speakerIdentityService: (any SpeakerIdentityMatching)? = nil,
        diarizationTimeoutSeconds: TimeInterval? = TranscriptionService.defaultDiarizationTimeoutSeconds,
        audioPreprocessor: any AudioPreprocessing = AppleSoundIsolationPreprocessor(),
        modelLoadTimeoutSeconds: TimeInterval? = TranscriptionService.defaultModelLoadTimeoutSeconds
    ) {
        self.storageLocations = storageLocations
        self.engineFactory = engineFactory ?? { provider in
            try TranscriptionService.defaultEngineFactory(provider: provider)
        }
        self.openAIAPIKeyProvider = openAIAPIKeyProvider
        self.speakerDiarizerFactory = diarizerFactory ?? { modelsDirectory in
            FluidSpeakerDiarizer(modelsDirectory: modelsDirectory)
        }
        self.voiceActivityDetectorFactory = voiceActivityDetectorFactory ?? { modelsDirectory in
            FluidVoiceActivityDetector(modelsDirectory: modelsDirectory)
        }
        self.streamingEngineFactory = streamingEngineFactory ?? { profile, modelsRoot in
            NemotronStreamingEngine(
                chunkProfile: profile,
                modelsRoot: modelsRoot
            )
        }
        self.appleSpeechEngineFactory = appleSpeechEngineFactory ?? {
            if #available(macOS 26.0, iOS 26.0, *) {
                return AppleSpeechTranscriberEngine()
            }
            return nil
        }
        self.streamingChunkProfileProvider = streamingChunkProfileProvider
        self.streamingBackendProvider = streamingBackendProvider
        self.speakerIdentityService = speakerIdentityService
        self.diarizationTimeoutSeconds = diarizationTimeoutSeconds
        self.audioPreprocessor = audioPreprocessor
        self.modelLoadTimeoutSeconds = modelLoadTimeoutSeconds
    }

    /// Replace the provider that resolves which streaming chunk profile to use. Safe to
    /// call post-init (AppCoordinator composes the TranscriptionService before the
    /// SettingsStore exists in its own init ordering).
    public func setStreamingChunkProfileProvider(_ provider: @escaping @MainActor () -> StreamingChunkProfile) {
        self.streamingChunkProfileProvider = provider
    }

    /// Replace the provider that resolves which streaming backend to use (Parakeet vs
    /// Apple SpeechTranscriber).
    public func setStreamingBackendProvider(_ provider: @escaping @MainActor () -> TranscriptionBackend) {
        self.streamingBackendProvider = provider
    }

    /// Read-and-clear the Apple fallback flag. Returns true exactly once after a
    /// fallback happens.
    public func consumeAppleBackendFallbackFlag() -> Bool {
        let value = appleBackendFellBackToParakeet
        appleBackendFellBackToParakeet = false
        return value
    }

    public func loadModel(modelName: String = "tiny", provider: ModelManager.ModelProvider = .whisperKit) async throws {
        try await loadBatchModel(.named(modelName: modelName, provider: provider))
    }

    private func performLoadModel(modelName: String, provider: ModelManager.ModelProvider) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }

        if currentProvider != nil && currentProvider != provider {
            await unloadModel()
        }

        state = .loading
        error = nil

        let loadStarted = CFAbsoluteTimeGetCurrent()
        Log.transcription.info("Loading model: \(modelName) with provider: \(provider.rawValue)...")
        Log.boot.info("TranscriptionService.loadModel begin name=\(modelName) provider=\(provider.rawValue) state=loading")

        do {
            let newEngine: any TranscriptionEngine
            if provider == .openAI {
                newEngine = OpenAITranscriptionEngine(apiKeyProvider: openAIAPIKeyProvider)
            } else {
                newEngine = try engineFactory(provider)
            }
            Log.boot.info("TranscriptionService.loadModel engine instance created provider=\(provider.rawValue) elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")

            try await loadModelWithOptionalWatchdog {
                Log.boot.info("TranscriptionService.loadModel engine.loadModel task started name=\(modelName)")
                let engineLoadStart = CFAbsoluteTimeGetCurrent()
                try await newEngine.loadModel(
                    name: modelName,
                    downloadBase: self.downloadBase(for: provider, modelName: modelName)
                )
                Log.boot.info("TranscriptionService.loadModel engine.loadModel task finished elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - engineLoadStart))")
            }

            engine = newEngine
            currentProvider = provider
            batchModelIdentity = .named(modelName: modelName, provider: provider)
            Log.transcription.info("Model loaded successfully with \(provider.rawValue) engine")
            Log.boot.info("TranscriptionService.loadModel success totalElapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            Log.boot.error("TranscriptionService.loadModel failed TranscriptionError after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted)) \(error.localizedDescription)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            Log.boot.error("TranscriptionService.loadModel failed after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted)) \(error.localizedDescription)")
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    public func loadModel(modelPath: String) async throws {
        try await loadBatchModel(.path(modelPath))
    }

    private func performLoadModel(modelPath: String) async throws {
        if state == .transcribing {
            throw TranscriptionError.engineSwitchDuringTranscription
        }

        if currentProvider != nil {
            await unloadModel()
        }

        state = .loading
        error = nil

        let loadStarted = CFAbsoluteTimeGetCurrent()
        Log.transcription.info("Loading model from path: \(modelPath) with prewarm enabled...")
        Log.boot.info("TranscriptionService.loadModel(path) begin")

        do {
            let newEngine = WhisperKitEngine()
            Log.boot.info("TranscriptionService.loadModel(path) WhisperKitEngine created elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")

            try await loadModelWithOptionalWatchdog {
                Log.boot.info("TranscriptionService.loadModel(path) engine.loadModel(path) task started")
                try await newEngine.loadModel(path: modelPath)
                Log.boot.info("TranscriptionService.loadModel(path) engine.loadModel(path) task finished")
            }

            engine = newEngine
            currentProvider = .whisperKit
            batchModelIdentity = .path(modelPath)
            Log.transcription.info("Model loaded and prewarmed successfully")
            Log.boot.info("TranscriptionService.loadModel(path) success totalElapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")
            state = .ready
        } catch let error as TranscriptionError {
            Log.transcription.error("Model load failed: \(error)")
            Log.boot.error("TranscriptionService.loadModel(path) TranscriptionError after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted)) \(error.localizedDescription)")
            self.error = error
            state = .error
            throw error
        } catch {
            Log.transcription.error("Model load failed: \(error)")
            let loadError = TranscriptionError.modelLoadFailed(error.localizedDescription)
            Log.boot.error("TranscriptionService.loadModel(path) failed after \(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted)) \(error.localizedDescription)")
            self.error = loadError
            state = .error
            throw loadError
        }
    }

    /// Serializes named/path model loading across actor reentrancy. A caller that
    /// arrives while another load is suspended awaits that identity's result and
    /// then re-evaluates state before starting a different load.
    private func loadBatchModel(_ identity: BatchModelIdentity) async throws {
        while true {
            guard state != .transcribing else {
                throw TranscriptionError.engineSwitchDuringTranscription
            }
            if engine != nil, batchModelIdentity == identity, state == .ready {
                return
            }
            if let handle = batchLoadHandle {
                let inFlightIdentity = handle.identity
                _ = try await handle.task.value
                if batchLoadHandle === handle { batchLoadHandle = nil }
                if inFlightIdentity == identity,
                   engine != nil,
                   batchModelIdentity == identity,
                   state == .ready {
                    return
                }
                continue
            }

            let task = Task { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                switch identity {
                case .named(let modelName, let provider):
                    try await self.performLoadModel(modelName: modelName, provider: provider)
                case .path(let modelPath):
                    try await self.performLoadModel(modelPath: modelPath)
                }
            }
            let handle = BatchLoadHandle(identity: identity, task: task)
            batchLoadHandle = handle
            do {
                try await task.value
            } catch {
                if batchLoadHandle === handle { batchLoadHandle = nil }
                throw error
            }
            if batchLoadHandle === handle { batchLoadHandle = nil }
            return
        }
    }

    public func transcribe(audioData: Data) async throws -> String {
        try await transcribe(audioData: audioData, options: TranscriptionOptions())
    }

    public func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await transcribe(audioData: audioData, diarizationEnabled: false, options: options).text
    }

    public func transcribe(audioData: Data, diarizationEnabled: Bool) async throws -> TranscriptionOutput {
        try await transcribe(
            audioData: audioData,
            diarizationEnabled: diarizationEnabled,
            options: TranscriptionOptions()
        )
    }

    public func transcribe(
        audioData: Data,
        diarizationEnabled: Bool,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        try await transcribe(
            audioData: audioData,
            diarizationEnabled: diarizationEnabled,
            options: options,
            diarizationOptions: .init(),
            diarizationFailurePolicy: .bestEffort
        )
    }

    public func transcribe(
        audioData: Data,
        diarizationEnabled: Bool,
        options: TranscriptionOptions,
        diarizationOptions: PindropCore.DiarizationOptions = .init(),
        diarizationFailurePolicy: DiarizationFailurePolicy = .bestEffort
    ) async throws -> TranscriptionOutput {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")

        try validateExpectedSpeakerCount(diarizationOptions.expectedSpeakerCount)

        try await ensureBatchEngineLoaded()
        guard let engine else { throw TranscriptionError.modelNotLoaded }

        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }

        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        let generation = nextTranscriptionGeneration
        nextTranscriptionGeneration &+= 1
        activeTranscriptionGeneration = generation
        state = .transcribing

        do {
            let transcriptionAudioData: Data
            if options.audioPreprocessingMode == .voiceIsolation {
                do {
                    let preprocessor = audioPreprocessor
                    let processedAudioData = try await withPromptCancellation {
                        try await preprocessor.process(
                            audioData: audioData,
                            mode: options.audioPreprocessingMode
                        )
                    }
                    try Task.checkCancellation()
                    transcriptionAudioData = processedAudioData
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    Log.transcription.warning(
                        "Voice isolation failed; continuing with raw audio: \(error.localizedDescription)"
                    )
                    transcriptionAudioData = audioData
                }
            } else {
                transcriptionAudioData = audioData
            }

            let floatCount = transcriptionAudioData.count / MemoryLayout<Float>.size
            let duration = Double(floatCount) / Double(Self.sampleRate)
            let providerName = currentProvider?.rawValue ?? "unknown"
            Log.transcription.info("Transcribing \(floatCount) samples (\(String(format: "%.2f", duration))s) using \(providerName)")

            let startTime = Date()

            let output = try await transcribeWithOptionalDiarization(
                engine: engine,
                audioData: transcriptionAudioData,
                sampleRate: Self.sampleRate,
                diarizationEnabled: diarizationEnabled,
                options: options,
                diarizationOptions: diarizationOptions,
                diarizationFailurePolicy: diarizationFailurePolicy
            )

            let elapsed = Date().timeIntervalSince(startTime)
            Log.transcription.info("Transcription completed in \(String(format: "%.2f", elapsed))s")

            finishTranscription(generation)
            Log.transcription.debug("Result redacted (chars=\(output.text.count), diarizedSegments=\(output.diarizedSegments?.count ?? 0))")
            return output
        } catch let error as TranscriptionError {
            finishTranscription(generation)
            throw error
        } catch is CancellationError {
            finishTranscription(generation)
            throw CancellationError()
        } catch {
            finishTranscription(generation)
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Transcribes one durable meeting chunk. The file is validated and read in
    /// bounded blocks before ASR; optional diarization can never replace a
    /// successfully produced plain transcript.
    /// - Parameter paragraphSegmentationEnabled: Cuts the chunk into paragraphs
    ///   at the pauses a voice activity detector hears. It applies only when
    ///   diarization is off, which is exactly the single-speaker case that has
    ///   no other structure to read. A missing or failing VAD model leaves the
    ///   chunk as one block: paragraph breaks are enrichment, never a reason to
    ///   fail a finished recording.
    public func transcribeMeetingChunk(
        _ input: TranscriptionChunkInput,
        options: TranscriptionOptions = .init(),
        diarizationOptions: PindropCore.DiarizationOptions = .init(),
        diarizationEnabled: Bool = true,
        paragraphSegmentationEnabled: Bool = false
    ) async throws -> TranscriptionChunkOutput {
        try Task.checkCancellation()
        if diarizationEnabled {
            try validateExpectedSpeakerCount(diarizationOptions.expectedSpeakerCount)
        }
        let audioData = try materializeMeetingChunk(input)
        try Task.checkCancellation()

        try await ensureBatchEngineLoaded()
        try Task.checkCancellation()
        guard let engine else { throw TranscriptionError.modelNotLoaded }
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        let generation = nextTranscriptionGeneration
        nextTranscriptionGeneration &+= 1
        activeTranscriptionGeneration = generation
        state = .transcribing

        do {
            try Task.checkCancellation()
            let plainText = try await engine.transcribe(audioData: audioData, options: options)
            try Task.checkCancellation()

            let diarization: (segments: [DiarizedTranscriptSegment]?, warning: String?)
            if diarizationEnabled {
                diarization = try await diarizeMeetingChunk(
                    engine: engine,
                    audioData: audioData,
                    options: options,
                    diarizationOptions: diarizationOptions
                )
            } else if paragraphSegmentationEnabled {
                diarization = (
                    await paragraphSegments(
                        text: plainText,
                        audioData: audioData,
                        chunkDuration: input.duration
                    ),
                    nil
                )
            } else {
                diarization = (nil, nil)
            }
            try Task.checkCancellation()

            let output = TranscriptionChunkOutput(
                chunkID: input.chunkID,
                sequence: input.sequence,
                startOffset: input.startOffset,
                duration: input.duration,
                plainText: plainText,
                diarizedSegments: diarization.segments,
                diarizationWarning: diarization.warning
            )
            finishTranscription(generation)
            return output
        } catch let error as TranscriptionError {
            finishTranscription(generation)
            throw error
        } catch is CancellationError {
            finishTranscription(generation)
            throw CancellationError()
        } catch {
            finishTranscription(generation)
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Combines persisted chunk results without assuming that diarizer-local
    /// speaker identifiers or segment times remain meaningful across chunks.
    public func mergeMeetingChunks(
        _ chunks: [TranscriptionChunkOutput]
    ) throws -> TranscriptionOutput {
        let sorted = chunks.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            if $0.startOffset != $1.startOffset { return $0.startOffset < $1.startOffset }
            return $0.chunkID.uuidString < $1.chunkID.uuidString
        }

        var seenSequences = Set<Int>()
        var previous: TranscriptionChunkOutput?
        var textParts: [String] = []
        var absoluteSegments: [(segment: DiarizedTranscriptSegment, sequence: Int, localIndex: Int)] = []

        for chunk in sorted {
            guard chunk.sequence >= 0,
                  chunk.startOffset.isFinite,
                  chunk.startOffset >= 0,
                  chunk.duration.isFinite,
                  chunk.duration >= 0 else {
                throw TranscriptionError.invalidMeetingChunk("Invalid sequence or timing for sequence \(chunk.sequence).")
            }
            guard seenSequences.insert(chunk.sequence).inserted else {
                throw TranscriptionError.duplicateMeetingChunkSequence(chunk.sequence)
            }

            if let previous {
                let expectedOffset = previous.startOffset + previous.duration
                let offsetDelta = chunk.startOffset - expectedOffset
                if offsetDelta < -Self.meetingChunkOffsetTolerance {
                    throw TranscriptionError.overlappingMeetingChunk(sequence: chunk.sequence)
                }
                if abs(offsetDelta) > Self.meetingChunkOffsetTolerance {
                    throw TranscriptionError.nonContiguousMeetingChunk(
                        expected: expectedOffset,
                        actual: chunk.startOffset,
                        sequence: chunk.sequence
                    )
                }
            }

            let normalizedText = normalizedMeetingText(chunk.plainText)
            if !normalizedText.isEmpty {
                textParts.append(normalizedText)
            }

            for (localIndex, segment) in (chunk.diarizedSegments ?? []).enumerated() {
                guard segment.startTime.isFinite,
                      segment.endTime.isFinite,
                      segment.startTime >= -Self.meetingChunkOffsetTolerance,
                      segment.endTime >= segment.startTime,
                      segment.endTime <= chunk.duration + Self.meetingChunkOffsetTolerance else {
                    throw TranscriptionError.invalidMeetingChunkSegmentBounds(sequence: chunk.sequence)
                }

                let localStart = max(segment.startTime, 0)
                let localEnd = min(segment.endTime, chunk.duration)
                absoluteSegments.append((
                    segment: DiarizedTranscriptSegment(
                        speakerId: "chunk-\(String(format: "%05d", chunk.sequence))/\(segment.speakerId)",
                        speakerLabel: segment.speakerLabel,
                        speakerProfileID: segment.speakerProfileID,
                        speakerEmbedding: segment.speakerEmbedding,
                        startTime: chunk.startOffset + localStart,
                        endTime: chunk.startOffset + localEnd,
                        confidence: segment.confidence,
                        text: segment.text
                    ),
                    sequence: chunk.sequence,
                    localIndex: localIndex
                ))
            }
            previous = chunk
        }

        absoluteSegments.sort {
            if $0.segment.startTime != $1.segment.startTime {
                return $0.segment.startTime < $1.segment.startTime
            }
            if $0.segment.endTime != $1.segment.endTime {
                return $0.segment.endTime < $1.segment.endTime
            }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.localIndex < $1.localIndex
        }

        return TranscriptionOutput(
            text: textParts.joined(separator: "\n"),
            diarizedSegments: absoluteSegments.isEmpty ? nil : absoluteSegments.map(\.segment)
        )
    }

    private func diarizeMeetingChunk(
        engine: any TranscriptionEngine,
        audioData: Data,
        options: TranscriptionOptions,
        diarizationOptions: PindropCore.DiarizationOptions
    ) async throws -> (segments: [DiarizedTranscriptSegment]?, warning: String?) {
        do {
            try Task.checkCancellation()
            let samples = await Self.floatSamples(from: audioData)
            try Task.checkCancellation()
            let diarizer = getOrCreateSpeakerDiarizer()
            try Task.checkCancellation()
            try await diarizer.loadModels()
            try Task.checkCancellation()
            let result = try await diarizeWithWatchdog(
                diarizer: diarizer,
                samples: samples,
                sampleRate: Self.sampleRate,
                options: diarizationOptions
            )
            try Task.checkCancellation()

            let segments = normalizedDiarizationSegments(
                result.segments,
                audioDuration: result.audioDuration
            )
            guard !segments.isEmpty else {
                return (nil, "Speaker diarization returned no usable segments.")
            }

            let diarizedOutput = try await transcribeBySpeakerSegments(
                engine: engine,
                samples: samples,
                sampleRate: Self.sampleRate,
                segments: segments,
                options: options
            )
            try Task.checkCancellation()
            guard let diarizedSegments = diarizedOutput.diarizedSegments, !diarizedSegments.isEmpty else {
                return (nil, "Speaker diarization produced no transcript text.")
            }
            return (diarizedSegments, nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (nil, "Speaker diarization unavailable: \(error.localizedDescription)")
        }
    }

    /// The paragraph spans of one single-speaker chunk, or nil when the chunk
    /// reads as one block.
    ///
    /// Nil is the ordinary answer for short chunks, for chunks with no pause in
    /// them, and for every install that does not have the VAD model on disk.
    /// Nothing here can fail a capture: a recording that finished is worth more
    /// than the paragraph breaks inside it.
    private func paragraphSegments(
        text: String,
        audioData: Data,
        chunkDuration: TimeInterval
    ) async -> [DiarizedTranscriptSegment]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        do {
            try Task.checkCancellation()
            let samples = await Self.floatSamples(from: audioData)
            try Task.checkCancellation()
            let detector = getOrCreateVoiceActivityDetector()
            try await detector.loadModel()
            try Task.checkCancellation()
            let speech = try await detector.segmentSpeech(
                in: samples,
                sampleRate: Self.sampleRate
            )
            try Task.checkCancellation()
            return SpeechParagraphSegmentation.paragraphSegments(
                text: text,
                voiceSegments: speech,
                chunkDuration: chunkDuration
            )
        } catch {
            Log.transcription.info(
                "Paragraph segmentation skipped: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func getOrCreateVoiceActivityDetector() -> any VoiceActivityDetector {
        if let voiceActivityDetector {
            return voiceActivityDetector
        }
        let created = voiceActivityDetectorFactory(
            storageLocations.fluidAudioModelsRoot
                .appendingPathComponent(FeatureModelType.vad.repoFolderName, isDirectory: true)
        )
        voiceActivityDetector = created
        return created
    }

    private func materializeMeetingChunk(_ input: TranscriptionChunkInput) throws -> Data {
        guard input.sequence >= 0,
              input.startOffset.isFinite,
              input.startOffset >= 0,
              input.duration.isFinite,
              input.duration > 0,
              input.byteCount > 0,
              input.byteCount <= Self.maximumMeetingChunkByteCount,
              input.byteCount.isMultiple(of: Self.bytesPerFloatSample),
              input.fileURL.isFileURL else {
            throw TranscriptionError.invalidMeetingChunk("Chunk metadata is not canonical.")
        }

        let sampleCount = input.byteCount / Self.bytesPerFloatSample
        let expectedDuration = Double(sampleCount) / Double(Self.sampleRate)
        guard abs(input.duration - expectedDuration) <= Self.meetingChunkOffsetTolerance else {
            throw TranscriptionError.invalidMeetingChunk("Declared duration does not match the PCM byte count.")
        }

        do {
            let values = try input.fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  values.fileSize == input.byteCount else {
                throw TranscriptionError.invalidMeetingChunk("File size does not match the sealed chunk metadata.")
            }

            let handle = try FileHandle(forReadingFrom: input.fileURL)
            defer { try? handle.close() }
            var bytesRead = 0
            var audioData = Data()
            audioData.reserveCapacity(input.byteCount)
            var hasher = SHA256()

            while let block = try handle.read(upToCount: Self.meetingChunkReadSize), !block.isEmpty {
                try Task.checkCancellation()
                bytesRead += block.count
                guard bytesRead <= input.byteCount else {
                    throw TranscriptionError.invalidMeetingChunk("File grew while it was being read.")
                }
                hasher.update(data: block)
                audioData.append(block)
            }

            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard bytesRead == input.byteCount,
                  audioData.count == input.byteCount,
                  digest == input.sha256 else {
                throw TranscriptionError.invalidMeetingChunk("File content does not match the sealed chunk metadata.")
            }
            return audioData
        } catch let error as TranscriptionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.invalidMeetingChunk(error.localizedDescription)
        }
    }

    private func normalizedMeetingText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Called by a hard deadline after it has cancelled a batch operation. The
    /// previous engine may still be executing and is never touched concurrently;
    /// dropping it forces the next batch operation to load a distinct engine.
    public func invalidateTimedOutTranscription() {
        guard activeTranscriptionGeneration != nil else { return }
        activeTranscriptionGeneration = nil
        engine = nil
        currentProvider = nil
        state = .unloaded
    }

    /// Restores a fresh engine after a hard deadline without touching the stale
    /// engine that may still be ignoring cancellation on another task.
    private func ensureBatchEngineLoaded() async throws {
        guard engine == nil else { return }
        guard let batchModelIdentity else {
            throw TranscriptionError.modelNotLoaded
        }
        switch batchModelIdentity {
        case .named(let modelName, let provider):
            try await loadModel(modelName: modelName, provider: provider)
        case .path(let modelPath):
            try await loadModel(modelPath: modelPath)
        }
    }

    public func extractSpeakerProfileSegments(audioData: Data) async throws -> [DiarizedTranscriptSegment] {
        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }

        let samples = await Self.floatSamples(from: audioData)
        let diarizer = getOrCreateSpeakerDiarizer()
        try await diarizer.loadModels()
        let result = try await diarizeWithWatchdog(
            diarizer: diarizer,
            samples: samples,
            sampleRate: Self.sampleRate,
            options: PindropCore.DiarizationOptions()
        )
        let segments = normalizedDiarizationSegments(
            result.segments,
            audioDuration: result.audioDuration
        )

        return segments.map { segment in
            DiarizedTranscriptSegment(
                speakerId: segment.speaker.id,
                speakerLabel: "",
                speakerEmbedding: segment.speaker.embedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: ""
            )
        }
    }

    public func unloadModel() async {
        // Publish the terminal boundary before any suspension. Engine operations
        // are cooperative, so their epoch/lease checks — not task cancellation —
        // prevent late completions from committing or being re-adopted.
        streamingLifecycleEpoch &+= 1
        appleBackendFellBackToParakeet = false
        streamingPrepareHandle?.task.cancel()
        streamingPrepareHandle = nil
        streamingResetHandle?.finish()
        streamingResetHandle = nil
        invalidateAndDiscardStreamingCallbackSource()

        let batchEngine = engine
        let diarizer = speakerDiarizer
        let streamingEngine = streamingEngine
        if let streamingEngine {
            beginStreamingEngineRetirement(streamingEngine)
        }
        engine = nil
        speakerDiarizer = nil
        self.streamingEngine = nil
        activeStreamingEngineIdentity = nil

        currentProvider = nil
        batchModelIdentity = nil
        state = .unloaded
        error = nil

        await batchEngine?.unloadModel()
        await diarizer?.unloadModels()
        if let streamingEngine {
            await streamingEngine.unloadModel()
            completeStreamingEngineRetirement(streamingEngine)
        }
    }

    public func setStreamingCallbacks(
        onPartial: StreamingEmissionSink? = nil,
        onFinalUtterance: StreamingEmissionSink? = nil
    ) {
        // Sinks are read live by the already-installed engine callbacks. Only
        // update the routing targets (and generation on clear) — never reinstall
        // invariant engine callbacks on every sink change.
        streamingPartialCallback = onPartial
        streamingFinalUtteranceCallback = onFinalUtterance
        if onPartial == nil && onFinalUtterance == nil {
            streamingCallbackDelivery.reset()
        }
    }

    public func prepareStreamingEngine() async throws {
        // A caller that began before unload must not become a fresh preparation
        // after the old shared task eventually resumes.
        let invocationEpoch = streamingLifecycleEpoch

        // Cancellation owns the engine until every prior operation drains and
        // reset returns. Only then may this epoch reactivate its callback source.
        while let reset = streamingResetHandle {
            guard reset.epoch == invocationEpoch,
                  let streamingEngine,
                  ObjectIdentifier(streamingEngine) == reset.engineID else {
                throw CancellationError()
            }
            await reset.wait()
            guard invocationEpoch == streamingLifecycleEpoch else {
                throw CancellationError()
            }
            if streamingResetHandle === reset {
                streamingResetHandle = nil
            }
        }

        // Wait out any in-flight preparation, then reconcile once more against
        // the settings as they are NOW — a caller landing mid-prewarm must not
        // inherit the backend/chunk profile captured when that prepare started.
        // The re-run is a cheap early-return when nothing changed. Errors from
        // the in-flight task are ignored here; our own run rethrows fresh ones.
        while let inFlight = streamingPrepareHandle {
            guard inFlight.epoch == invocationEpoch else {
                throw CancellationError()
            }
            _ = try? await inFlight.task.value
            guard invocationEpoch == streamingLifecycleEpoch else {
                throw CancellationError()
            }
            if streamingPrepareHandle === inFlight { streamingPrepareHandle = nil }
        }

        guard invocationEpoch == streamingLifecycleEpoch else {
            throw CancellationError()
        }
        let task = Task {
            try await performPrepareStreamingEngine(epoch: invocationEpoch)
        }
        let handle = StreamingPrepareHandle(epoch: invocationEpoch, task: task)
        streamingPrepareHandle = handle
        defer { if streamingPrepareHandle === handle { streamingPrepareHandle = nil } }
        try await task.value
    }

    private func performPrepareStreamingEngine(epoch: UInt64) async throws {
        try requireCurrentStreamingLifecycle(epoch)
        let profile = streamingChunkProfileProvider()
        let requestedBackend = streamingBackendProvider()
        let resolvedAppleEngine: (any StreamingTranscriptionEngine)? =
            requestedBackend == .appleSpeechTranscriber ? appleSpeechEngineFactory() : nil

        // Resolve the backend we can actually run. Apple's SpeechTranscriber only
        // exists on macOS 26+; older hosts fall back to Parakeet.
        let effectiveBackend: TranscriptionBackend
        if requestedBackend == .appleSpeechTranscriber, resolvedAppleEngine == nil {
            effectiveBackend = .parakeet
            appleBackendFellBackToParakeet = true
            Log.transcription.warning(
                "Apple SpeechTranscriber requested but unavailable on this host; falling back to Nemotron"
            )
        } else {
            effectiveBackend = requestedBackend
        }

        // Recreate when the backend changes or Nemotron's chunk profile changes.
        // The lease makes every await below part of this epoch's ownership.
        if let existing = streamingEngine {
            let lease = try acquireOwnedStreamingEngineLease(existing, epoch: epoch)
            do {
                let existingBackend = Self.backendFor(engine: existing)
                var recreate = existingBackend != effectiveBackend
                if !recreate, effectiveBackend == .parakeet,
                   let nemotron = existing as? NemotronStreamingEngine {
                    let existingProfile = await nemotron.chunkProfile
                    try requireCurrentStreamingLifecycle(epoch, owning: existing)
                    if existingProfile != profile {
                        await nemotron.updateChunkProfile(profile)
                        try requireCurrentStreamingLifecycle(epoch, owning: existing)
                        recreate = true
                    }
                }

                if recreate {
                    invalidateAndDiscardStreamingCallbackSource()
                    streamingEngine = nil
                    activeStreamingEngineIdentity = nil

                    beginStreamingEngineRetirement(existing)
                    await existing.unloadModel()
                    completeStreamingEngineRetirement(existing)
                    releaseStreamingEngineLease(lease)
                    try requireCurrentStreamingLifecycle(epoch)
                } else {
                    releaseStreamingEngineLease(lease)
                }
            } catch {
                if !isCurrentStreamingLifecycle(epoch, owning: existing) {
                    await finalizeStaleStreamingEngineLease(lease)
                    throw CancellationError()
                }
                releaseStreamingEngineLease(lease)
                throw error
            }
        }

        let preparedEngine: any StreamingTranscriptionEngine
        let lease: StreamingEngineLease
        if let existing = streamingEngine {
            preparedEngine = existing
            lease = try acquireOwnedStreamingEngineLease(existing, epoch: epoch)
        } else {
            switch effectiveBackend {
            case .parakeet:
                preparedEngine = streamingEngineFactory(profile, self.storageLocations.fluidAudioModelsRoot)
            case .appleSpeechTranscriber:
                guard let resolvedAppleEngine else {
                    throw TranscriptionError.streamingNotReady
                }
                preparedEngine = resolvedAppleEngine
            }
            lease = try await acquireStreamingEngineAdoptionLease(
                preparedEngine,
                epoch: epoch
            )
        }

        do {
            let source = try await callbackSource(
                for: preparedEngine,
                lifecycleEpoch: epoch
            )
            try requireCurrentStreamingLifecycle(epoch)
            if streamingEngine == nil {
                streamingEngine = preparedEngine
            }
            try requireCurrentStreamingLifecycle(epoch, owning: preparedEngine)
            streamingCallbackSource = source
            let preparedIdentity = Self.streamingEngineIdentity(
                backend: effectiveBackend,
                profile: profile
            )


            let engineState = await preparedEngine.state
            try requireCurrentStreamingLifecycle(epoch, owning: preparedEngine)
            switch engineState {
            case .ready, .streaming, .paused:
                activeStreamingEngineIdentity = preparedIdentity

                releaseStreamingEngineLease(lease)
                if state == .unloaded || state == .error {
                    state = .ready
                }
                return
            case .loading:
                releaseStreamingEngineLease(lease)
                return
            case .unloaded, .error:
                break
            }

            // Model path is only relevant for Parakeet; Apple ignores `name`.
            let modelPath: String
            switch effectiveBackend {
            case .parakeet:
                modelPath = FeatureModelType.streamingRepoFolderName(for: profile)
            case .appleSpeechTranscriber:
                modelPath = ""
            }

            do {
                try await preparedEngine.loadModel(name: modelPath)
                try requireCurrentStreamingLifecycle(epoch, owning: preparedEngine)
                activeStreamingEngineIdentity = preparedIdentity

                releaseStreamingEngineLease(lease)
                if state == .unloaded || state == .error {
                    state = .ready
                }
            } catch {
                guard isCurrentStreamingLifecycle(epoch, owning: preparedEngine) else {
                    await finalizeStaleStreamingEngineLease(lease)
                    throw CancellationError()
                }
                releaseStreamingEngineLease(lease)
                if error is CancellationError {
                    throw CancellationError()
                }

                // Preserve the underlying diagnostic in logs while exposing the
                // existing service-level error contract.
                Log.transcription.error(
                    "Streaming engine load failed for \(modelPath): \(error.localizedDescription)"
                )
                let streamingError: TranscriptionError
                switch effectiveBackend {
                case .parakeet:
                    let path = self.storageLocations.fluidAudioModelsRoot
                        .appendingPathComponent(modelPath, isDirectory: true)
                        .path
                    streamingError = .streamingModelNotAvailable(path)
                case .appleSpeechTranscriber:
                    streamingError = .streamingStartFailed(error.localizedDescription)
                }
                self.error = streamingError
                if state == .unloaded || state == .error {
                    state = .error
                }
                throw streamingError
            }
        } catch {
            guard isCurrentStreamingLifecycle(epoch, owning: preparedEngine) else {
                await finalizeStaleStreamingEngineLease(lease)
                throw CancellationError()
            }
            releaseStreamingEngineLease(lease)
            throw error
        }
    }

    private func requireCurrentStreamingLifecycle(
        _ expectedEpoch: UInt64,
        owning expectedEngine: (any StreamingTranscriptionEngine)? = nil
    ) throws {
        guard expectedEpoch == streamingLifecycleEpoch else {
            throw CancellationError()
        }
        if let expectedEngine {
            guard streamingEngine === expectedEngine else {
                throw CancellationError()
            }
        }
    }

    private func isCurrentStreamingLifecycle(
        _ expectedEpoch: UInt64,
        owning expectedEngine: (any StreamingTranscriptionEngine)? = nil
    ) -> Bool {
        guard expectedEpoch == streamingLifecycleEpoch else { return false }
        guard let expectedEngine else { return true }
        return streamingEngine === expectedEngine
    }

    private func acquireOwnedStreamingEngineLease(
        _ engine: any StreamingTranscriptionEngine,
        epoch: UInt64
    ) throws -> StreamingEngineLease {
        try requireCurrentStreamingLifecycle(epoch, owning: engine)
        let identity = ObjectIdentifier(engine)
        guard !retiredStreamingEngineIdentities.contains(identity) else {
            throw CancellationError()
        }
        streamingEngineLeaseCounts[identity, default: 0] += 1
        return StreamingEngineLease(engine: engine, epoch: epoch)
    }

    private func acquireStreamingEngineAdoptionLease(
        _ engine: any StreamingTranscriptionEngine,
        epoch: UInt64
    ) async throws -> StreamingEngineLease {
        let identity = ObjectIdentifier(engine)
        while retiredStreamingEngineIdentities.contains(identity)
            || streamingEngineLeaseCounts[identity, default: 0] > 0 {
            await withCheckedContinuation { continuation in
                streamingEngineAvailabilityWaiters[identity, default: []].append(continuation)
            }
            try requireCurrentStreamingLifecycle(epoch)
        }
        try requireCurrentStreamingLifecycle(epoch)
        guard streamingEngine == nil else {
            throw CancellationError()
        }
        streamingEngineLeaseCounts[identity, default: 0] += 1
        return StreamingEngineLease(engine: engine, epoch: epoch)
    }

    private func releaseStreamingEngineLease(_ lease: StreamingEngineLease) {
        guard !lease.isReleased else { return }
        lease.isReleased = true
        let identity = lease.identity
        let remaining = streamingEngineLeaseCounts[identity, default: 0] - 1
        if remaining > 0 {
            streamingEngineLeaseCounts[identity] = remaining
            return
        }
        streamingEngineLeaseCounts.removeValue(forKey: identity)
        let drainWaiters = streamingEngineLeaseDrainWaiters.removeValue(forKey: identity) ?? []
        for waiter in drainWaiters {
            waiter.resume()
        }
        makeStreamingEngineIdentityAvailableIfPossible(identity)
    }

    private func finalizeStaleStreamingEngineLease(_ lease: StreamingEngineLease) async {
        guard !lease.isReleased else { return }
        // Adoption waits for this lease, so cleanup can never target a newer owner
        // even when a factory repeatedly returns the exact same object.
        if streamingEngine !== lease.engine {
            await lease.engine.unloadModel()
        }
        releaseStreamingEngineLease(lease)
    }

    private func waitForStreamingEngineLeasesToDrain(
        _ engine: any StreamingTranscriptionEngine,
        epoch: UInt64
    ) async throws {
        let identity = ObjectIdentifier(engine)
        while streamingEngineLeaseCounts[identity, default: 0] > 0 {
            await withCheckedContinuation { continuation in
                streamingEngineLeaseDrainWaiters[identity, default: []].append(continuation)
            }
            try requireCurrentStreamingLifecycle(epoch, owning: engine)
        }
    }

    private func beginStreamingEngineRetirement(_ engine: any StreamingTranscriptionEngine) {
        let identity = ObjectIdentifier(engine)
        retiredStreamingEngineIdentities.insert(identity)
        streamingRetirementCleanupCounts[identity, default: 0] += 1
        // A reset waiting for old leases must observe teardown immediately rather
        // than waiting forever for a non-cooperative operation.
        let drainWaiters = streamingEngineLeaseDrainWaiters.removeValue(forKey: identity) ?? []
        for waiter in drainWaiters {
            waiter.resume()
        }
    }

    private func completeStreamingEngineRetirement(_ engine: any StreamingTranscriptionEngine) {
        let identity = ObjectIdentifier(engine)
        let remaining = streamingRetirementCleanupCounts[identity, default: 0] - 1
        if remaining > 0 {
            streamingRetirementCleanupCounts[identity] = remaining
        } else {
            streamingRetirementCleanupCounts.removeValue(forKey: identity)
        }
        makeStreamingEngineIdentityAvailableIfPossible(identity)
    }

    private func makeStreamingEngineIdentityAvailableIfPossible(_ identity: ObjectIdentifier) {
        guard streamingEngineLeaseCounts[identity, default: 0] == 0,
              streamingRetirementCleanupCounts[identity, default: 0] == 0 else {
            return
        }
        retiredStreamingEngineIdentities.remove(identity)
        let waiters = streamingEngineAvailabilityWaiters.removeValue(forKey: identity) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func invalidateAndDiscardStreamingCallbackSource() {
        streamingCallbackDelivery.invalidateCurrentSource()
        streamingCallbackSource = nil
    }

    /// Map an existing engine instance back to the `TranscriptionBackend` that produced it.
    private static func backendFor(engine: any StreamingTranscriptionEngine) -> TranscriptionBackend {
        if engine is NemotronStreamingEngine {
            return .parakeet
        }
        if #available(macOS 26.0, iOS 26.0, *) {
            if engine is AppleSpeechTranscriberEngine {
                return .appleSpeechTranscriber
            }
        }
        return .parakeet
    }

    private static func streamingEngineIdentity(
        backend: TranscriptionBackend,
        profile: StreamingChunkProfile
    ) -> StreamingEngineIdentity {
        switch backend {
        case .parakeet:
            StreamingEngineIdentity(
                providerIdentifier: TranscriptionBackend.parakeet.rawValue,
                modelIdentifier: profile.repoFolderName
            )
        case .appleSpeechTranscriber:
            StreamingEngineIdentity(
                providerIdentifier: TranscriptionBackend.appleSpeechTranscriber.rawValue,
                modelIdentifier: "apple-speech-transcriber/progressive"
            )
        }
    }

    public func startStreaming() async throws {
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }
        let invocationEpoch = streamingLifecycleEpoch

        do {
            try await prepareStreamingEngine()
            try requireCurrentStreamingLifecycle(invocationEpoch)
            guard let streamingEngine else {
                throw TranscriptionError.streamingNotReady
            }
            let lease = try acquireOwnedStreamingEngineLease(
                streamingEngine,
                epoch: invocationEpoch
            )
            do {
                try await streamingEngine.startStreaming()
                guard isCurrentStreamingLifecycle(invocationEpoch, owning: streamingEngine) else {
                    await finalizeStaleStreamingEngineLease(lease)
                    throw CancellationError()
                }
                releaseStreamingEngineLease(lease)
                state = .transcribing
                error = nil
            } catch {
                guard isCurrentStreamingLifecycle(invocationEpoch, owning: streamingEngine) else {
                    await finalizeStaleStreamingEngineLease(lease)
                    throw CancellationError()
                }
                releaseStreamingEngineLease(lease)
                throw error
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let transcriptionError as TranscriptionError {
            try requireCurrentStreamingLifecycle(invocationEpoch)
            self.error = transcriptionError
            throw transcriptionError
        } catch {
            try requireCurrentStreamingLifecycle(invocationEpoch)
            let streamingError = TranscriptionError.streamingStartFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    public func processStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard state == .transcribing, let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }
        let epoch = streamingLifecycleEpoch
        let lease = try acquireOwnedStreamingEngineLease(streamingEngine, epoch: epoch)

        do {
            try await streamingEngine.processAudioBuffer(buffer)
            guard isCurrentStreamingLifecycle(epoch, owning: streamingEngine) else {
                await finalizeStaleStreamingEngineLease(lease)
                throw CancellationError()
            }
            releaseStreamingEngineLease(lease)
        } catch {
            guard isCurrentStreamingLifecycle(epoch, owning: streamingEngine) else {
                await finalizeStaleStreamingEngineLease(lease)
                throw CancellationError()
            }
            releaseStreamingEngineLease(lease)
            if error is CancellationError {
                throw CancellationError()
            }
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            }
            let streamingError = TranscriptionError.streamingProcessingFailed(
                error.localizedDescription
            )
            self.error = streamingError
            throw streamingError
        }
    }

    public func stopStreaming() async throws -> String {
        guard state == .transcribing, let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }
        let epoch = streamingLifecycleEpoch
        let lease = try acquireOwnedStreamingEngineLease(streamingEngine, epoch: epoch)

        do {
            let finalText = try await streamingEngine.stopStreaming()
            guard isCurrentStreamingLifecycle(epoch, owning: streamingEngine) else {
                await finalizeStaleStreamingEngineLease(lease)
                throw CancellationError()
            }
            releaseStreamingEngineLease(lease)
            state = .ready
            return finalText
        } catch {
            guard isCurrentStreamingLifecycle(epoch, owning: streamingEngine) else {
                await finalizeStaleStreamingEngineLease(lease)
                throw CancellationError()
            }
            releaseStreamingEngineLease(lease)
            state = .ready
            if error is CancellationError {
                throw CancellationError()
            }
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            }
            let streamingError = TranscriptionError.streamingStopFailed(
                error.localizedDescription
            )
            self.error = streamingError
            throw streamingError
        }
    }

    private func performStreamingResetBarrier(
        on streamingEngine: any StreamingTranscriptionEngine,
        epoch: UInt64
    ) async -> Bool {
        guard let lease = try? acquireOwnedStreamingEngineLease(
            streamingEngine,
            epoch: epoch
        ) else {
            return false
        }
        await streamingEngine.reset()
        guard isCurrentStreamingLifecycle(epoch, owning: streamingEngine) else {
            await finalizeStaleStreamingEngineLease(lease)
            return false
        }
        releaseStreamingEngineLease(lease)
        return true
    }

    public func cancelStreaming() async {
        // Cancellation is a new lifecycle/session epoch. Publish it and deactivate
        // delivery before awaiting any potentially non-cooperative engine work.
        streamingLifecycleEpoch &+= 1
        appleBackendFellBackToParakeet = false
        let resetEpoch = streamingLifecycleEpoch
        streamingPrepareHandle?.task.cancel()
        streamingPrepareHandle = nil
        streamingResetHandle?.finish()
        streamingCallbackDelivery.invalidateSource(streamingCallbackSource)

        guard let streamingEngine else {
            streamingResetHandle = nil
            state = engine == nil ? .unloaded : .ready
            return
        }

        state = .ready
        let resetHandle = StreamingResetHandle(epoch: resetEpoch, engine: streamingEngine)
        streamingResetHandle = resetHandle
        let identity = ObjectIdentifier(streamingEngine)
        let hasPriorOperations = streamingEngineLeaseCounts[identity, default: 0] > 0

        do {
            if hasPriorOperations {
                // First interrupt cooperative engine work that only completes in
                // response to reset. Delivery stays inactive, and this is not the
                // final session barrier because an old operation may resume late.
                guard await performStreamingResetBarrier(
                    on: streamingEngine,
                    epoch: resetEpoch
                ) else {
                    throw CancellationError()
                }
            }

            try await waitForStreamingEngineLeasesToDrain(
                streamingEngine,
                epoch: resetEpoch
            )

            // Reset once more after every prior lease has completed. This is the
            // true callback/state barrier that preparation waits on before source
            // reactivation.
            guard await performStreamingResetBarrier(
                on: streamingEngine,
                epoch: resetEpoch
            ) else {
                throw CancellationError()
            }
        } catch {
            // Unload/replacement owns the state now. Its retirement lease prevents
            // this abandoned identity from being adopted until cleanup completes.
        }

        resetHandle.finish()
        if streamingResetHandle === resetHandle {
            streamingResetHandle = nil
        }
    }

    private func transcribeWithOptionalDiarization(
        engine: any TranscriptionEngine,
        audioData: Data,
        sampleRate: Int,
        diarizationEnabled: Bool,
        options: TranscriptionOptions,
        diarizationOptions: PindropCore.DiarizationOptions,
        diarizationFailurePolicy: DiarizationFailurePolicy
    ) async throws -> TranscriptionOutput {
        guard diarizationEnabled else {
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData, options: options)
        }

        Log.transcription.info("Speaker diarization enabled for current transcription")

        do {
            try Task.checkCancellation()
            // Sample conversion is only needed for diarization / per-segment slicing.
            let samples = await Self.floatSamples(from: audioData)
            try Task.checkCancellation()
            let diarizer = getOrCreateSpeakerDiarizer()
            try Task.checkCancellation()
            try await diarizer.loadModels()
            try Task.checkCancellation()

            let diarizationStarted = CFAbsoluteTimeGetCurrent()
            let diarizationResult = try await diarizeWithWatchdog(
                diarizer: diarizer,
                samples: samples,
                sampleRate: sampleRate,
                options: diarizationOptions
            )
            let processingDuration = CFAbsoluteTimeGetCurrent() - diarizationStarted
            try Task.checkCancellation()

            let normalizedSegments = normalizedDiarizationSegments(
                diarizationResult.segments,
                audioDuration: diarizationResult.audioDuration
            )
            let observedSpeakerCount = Set(normalizedSegments.map(\PindropCore.SpeakerSegment.speaker.id)).count
            logDiarizationDiagnostics(
                requestedSpeakerCount: diarizationOptions.expectedSpeakerCount,
                observedSpeakerCount: observedSpeakerCount,
                audioDuration: diarizationResult.audioDuration,
                processingDuration: processingDuration
            )

            guard !normalizedSegments.isEmpty else {
                return try await handleDiarizationFallback(
                    engine: engine,
                    audioData: audioData,
                    options: options,
                    policy: diarizationFailurePolicy,
                    reason: "Speaker diarization returned no usable segments."
                )
            }

            let output = try await transcribeBySpeakerSegments(
                engine: engine,
                samples: samples,
                sampleRate: sampleRate,
                segments: normalizedSegments,
                options: options
            )

            if let diarizedSegments = output.diarizedSegments, !diarizedSegments.isEmpty {
                Log.transcription.info("Speaker diarization succeeded with \(diarizedSegments.count) segments")
                return output
            }

            return try await handleDiarizationFallback(
                engine: engine,
                audioData: audioData,
                options: options,
                policy: diarizationFailurePolicy,
                reason: "Speaker diarization produced no transcript text."
            )
        } catch is CancellationError {
            Log.transcription.info("Speaker diarization canceled")
            throw CancellationError()
        } catch let error as TranscriptionError {
            throw error
        } catch {
            return try await handleDiarizationFallback(
                engine: engine,
                audioData: audioData,
                options: options,
                policy: diarizationFailurePolicy,
                reason: error.localizedDescription
            )
        }
    }

    private func handleDiarizationFallback(
        engine: any TranscriptionEngine,
        audioData: Data,
        options: TranscriptionOptions,
        policy: DiarizationFailurePolicy,
        reason: String
    ) async throws -> TranscriptionOutput {
        switch policy {
        case .required:
            Log.transcription.error("Speaker diarization required but failed: \(reason)")
            throw TranscriptionError.diarizationFailed(reason)
        case .bestEffort:
            Log.transcription.warning("Speaker diarization unavailable, falling back to plain transcript: \(reason)")
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData, options: options)
        }
    }

    private func finishTranscription(_ generation: UInt64) {
        guard activeTranscriptionGeneration == generation else { return }
        activeTranscriptionGeneration = nil
        state = .ready
    }

    private func diarizeWithWatchdog(
        diarizer: any SpeakerDiarizer,
        samples: [Float],
        sampleRate: Int,
        options: PindropCore.DiarizationOptions
    ) async throws -> PindropCore.DiarizationResult {
        guard let timeoutSeconds = diarizationTimeoutSeconds else {
            return try await diarizer.diarize(samples: samples, sampleRate: sampleRate, options: options)
        }

        return try await withAsyncWatchdog(
            timeoutSeconds: timeoutSeconds,
            timeoutError: { DiarizationTimeoutError(timeoutSeconds: timeoutSeconds) }
        ) {
            try await diarizer.diarize(samples: samples, sampleRate: sampleRate, options: options)
        }
    }

    private func transcribeWithoutDiarization(
        engine: any TranscriptionEngine,
        audioData: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        let text = try await engine.transcribe(audioData: audioData, options: options)
        return TranscriptionOutput(text: text, diarizedSegments: nil)
    }

    private func transcribeBySpeakerSegments(
        engine: any TranscriptionEngine,
        samples: [Float],
        sampleRate: Int,
        segments: [PindropCore.SpeakerSegment],
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        let identityMatchesByID = try matchedSpeakerIdentitiesByID(from: segments)
        var genericLabelsByID: [String: String] = [:]
        var fallbackSpeakerIndex = 1
        let segmentOptions = await transcriptionOptionsForDiarizedSegments(
            engine: engine,
            samples: samples,
            sampleRate: sampleRate,
            options: options
        )
        var transcriptSegments: [DiarizedTranscriptSegment] = []
        var transcribedSpeakerIDs = Set<String>()
        var textLines: [String] = []

        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            let previousEnd = index > 0 ? segments[index - 1].endTime : nil
            let nextStart = index + 1 < segments.count ? segments[index + 1].startTime : nil
            guard let segmentData = extractAudioData(
                samples: samples,
                sampleRate: sampleRate,
                startTime: segment.startTime,
                endTime: segment.endTime,
                previousEndTime: previousEnd,
                nextStartTime: nextStart
            ) else {
                continue
            }

            let segmentText = try await engine.transcribe(audioData: segmentData, options: segmentOptions)
            let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let speakerID = segment.speaker.id
            let identityMatch = identityMatchesByID[speakerID]
            let resolvedSpeakerLabel: String
            if let identityMatch {
                resolvedSpeakerLabel = identityMatch.displayName
            } else if let existingLabel = genericLabelsByID[speakerID] {
                resolvedSpeakerLabel = existingLabel
            } else {
                resolvedSpeakerLabel = "Speaker \(fallbackSpeakerIndex)"
                genericLabelsByID[speakerID] = resolvedSpeakerLabel
                fallbackSpeakerIndex += 1
            }
            transcribedSpeakerIDs.insert(speakerID)

            let diarizedSegment = DiarizedTranscriptSegment(
                speakerId: speakerID,
                speakerLabel: resolvedSpeakerLabel,
                speakerProfileID: identityMatch?.profileID,
                speakerEmbedding: segment.speaker.embedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: trimmed
            )

            let splitSegments = splitTranscriptSegmentIfNeeded(diarizedSegment)
            transcriptSegments.append(contentsOf: splitSegments)
            textLines.append(contentsOf: splitSegments.map { "\(resolvedSpeakerLabel): \($0.text)" })
        }

        let shouldShowSpeakerLabels = transcribedSpeakerIDs.count > 1
        let visibleSegments: [DiarizedTranscriptSegment]
        let mergedText: String
        if shouldShowSpeakerLabels {
            visibleSegments = transcriptSegments
            mergedText = textLines.joined(separator: "\n")
        } else {
            if !transcriptSegments.isEmpty {
                Log.transcription.info("Speaker diarization detected a single speaker; omitting labels from transcript output")
            }
            // Preserve accepted profile IDs even when labels are hidden for single-speaker output.
            visibleSegments = transcriptSegments.map { segment in
                DiarizedTranscriptSegment(
                    speakerId: segment.speakerId,
                    speakerLabel: "",
                    speakerProfileID: segment.speakerProfileID,
                    speakerEmbedding: segment.speakerEmbedding,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence,
                    text: segment.text
                )
            }
            mergedText = visibleSegments
                .map(\.text)
                .joined(separator: " ")
        }

        return TranscriptionOutput(
            text: mergedText,
            diarizedSegments: visibleSegments.isEmpty ? nil : visibleSegments
        )
    }

    private func transcriptionOptionsForDiarizedSegments(
        engine: any TranscriptionEngine,
        samples: [Float],
        sampleRate: Int,
        options: TranscriptionOptions
    ) async -> TranscriptionOptions {
        // Reapplying the vocabulary prompt to every diarized slice can make it dominate
        // short or noisy segments and leak the prompt itself into the transcript.
        let unbiasedOptions = TranscriptionOptions(language: options.language)
        guard options.language == .automatic else {
            return unbiasedOptions
        }

        do {
            guard let detectedLanguage = try await engine.detectLanguage(samples: samples, sampleRate: sampleRate),
                  detectedLanguage != .automatic else {
                return unbiasedOptions
            }

            Log.transcription.info("Pinned detected language for diarized transcription segments: \(detectedLanguage.rawValue)")
            return TranscriptionOptions(language: detectedLanguage)
        } catch {
            Log.transcription.warning(
                "Language detection for diarized transcription failed; using per-segment automatic detection: \(error.localizedDescription)"
            )
            return unbiasedOptions
        }
    }


    private func matchedSpeakerIdentitiesByID(
        from segments: [PindropCore.SpeakerSegment]
    ) throws -> [String: SpeakerIdentityMatch] {
        guard let speakerIdentityService else { return [:] }

        var segmentsBySpeakerID: [String: [PindropCore.SpeakerSegment]] = [:]
        for segment in segments {
            try Task.checkCancellation()
            segmentsBySpeakerID[segment.speaker.id, default: []].append(segment)
        }

        // Request-scoped match batch: one aggregate embedding per speaker plus every
        // eligible consensus embedding, resolved against a single profile snapshot.
        struct PendingSpeaker {
            let speakerID: String
            let aggregateEmbeddingIndex: Int
            let consensusEmbeddingIndices: [Int]
            let consensusWeights: [Float]
            let consensusDurations: [TimeInterval]
        }

        var embeddings: [[Float]] = []
        var pendingSpeakers: [PendingSpeaker] = []
        embeddings.reserveCapacity(segmentsBySpeakerID.count)
        pendingSpeakers.reserveCapacity(segmentsBySpeakerID.count)

        for (speakerID, speakerSegments) in segmentsBySpeakerID {
            try Task.checkCancellation()
            guard let aggregateEmbedding = weightedAggregateEmbedding(from: speakerSegments) else {
                continue
            }

            let aggregateEmbeddingIndex = embeddings.count
            embeddings.append(aggregateEmbedding)

            var consensusEmbeddingIndices: [Int] = []
            var consensusWeights: [Float] = []
            var consensusDurations: [TimeInterval] = []
            consensusEmbeddingIndices.reserveCapacity(speakerSegments.count)
            consensusWeights.reserveCapacity(speakerSegments.count)
            consensusDurations.reserveCapacity(speakerSegments.count)

            for segment in speakerSegments {
                try Task.checkCancellation()
                guard segment.duration >= Self.identityEligibleSegmentDurationSeconds,
                      segment.confidence >= Self.identityEligibleSegmentConfidence,
                      let embedding = validEmbedding(segment.speaker.embedding) else {
                    continue
                }

                let weight = Float(max(segment.duration, 0)) * max(segment.confidence, 0)
                guard weight.isFinite, weight > 0 else { continue }

                consensusEmbeddingIndices.append(embeddings.count)
                embeddings.append(embedding)
                consensusWeights.append(weight)
                consensusDurations.append(segment.duration)
            }

            pendingSpeakers.append(
                PendingSpeaker(
                    speakerID: speakerID,
                    aggregateEmbeddingIndex: aggregateEmbeddingIndex,
                    consensusEmbeddingIndices: consensusEmbeddingIndices,
                    consensusWeights: consensusWeights,
                    consensusDurations: consensusDurations
                )
            )
        }

        guard !pendingSpeakers.isEmpty else { return [:] }

        let matches = try speakerIdentityService.bestMatches(for: embeddings)
        guard matches.count == embeddings.count else {
            // Defensive: protocol contract requires 1:1 cardinality with input order.
            return [:]
        }

        var matchesByID: [String: SpeakerIdentityMatch] = [:]
        matchesByID.reserveCapacity(pendingSpeakers.count)

        for pending in pendingSpeakers {
            try Task.checkCancellation()
            guard let aggregateMatch = matches[pending.aggregateEmbeddingIndex] else {
                continue
            }

            guard hasSegmentConsensus(
                for: aggregateMatch,
                matchResults: pending.consensusEmbeddingIndices.map { matches[$0] },
                weights: pending.consensusWeights,
                durations: pending.consensusDurations
            ) else {
                continue
            }

            matchesByID[pending.speakerID] = aggregateMatch
        }

        return matchesByID
    }

    private func weightedAggregateEmbedding(from segments: [PindropCore.SpeakerSegment]) -> [Float]? {
        var weightedEmbeddings: [(embedding: [Float], weight: Float)] = []
        weightedEmbeddings.reserveCapacity(segments.count)

        for segment in segments {
            guard let embedding = validEmbedding(segment.speaker.embedding) else { continue }
            let weight = Float(max(segment.duration, 0)) * max(segment.confidence, 0)
            weightedEmbeddings.append((embedding, weight))
        }

        guard let dimension = weightedEmbeddings.first?.embedding.count,
              dimension > 0,
              weightedEmbeddings.allSatisfy({ $0.embedding.count == dimension }) else {
            return nil
        }

        let totalWeight = weightedEmbeddings.reduce(Float(0)) { $0 + $1.weight }
        let useEqualWeights = !totalWeight.isFinite || totalWeight <= 0
        var aggregate = Array(repeating: Float(0), count: dimension)
        var appliedWeight: Float = 0

        for item in weightedEmbeddings {
            let weight = useEqualWeights ? 1 : item.weight
            guard weight.isFinite, weight > 0 else { continue }
            appliedWeight += weight
            for index in 0..<dimension {
                let value = item.embedding[index]
                guard value.isFinite else { continue }
                aggregate[index] += value * weight
            }
        }

        guard appliedWeight.isFinite, appliedWeight > 0 else { return nil }
        for index in 0..<dimension {
            aggregate[index] /= appliedWeight
            guard aggregate[index].isFinite else { return nil }
        }
        return aggregate
    }

    /// Consensus gate over already-resolved batch matches (no additional identity lookups).
    private func hasSegmentConsensus(
        for aggregateMatch: SpeakerIdentityMatch,
        matchResults: [SpeakerIdentityMatch?],
        weights: [Float],
        durations: [TimeInterval]
    ) -> Bool {
        var agreeingWeight: Float = 0
        var totalWeight: Float = 0
        var hasLongAgreeingSegment = false
        var eligibleSegmentCount = 0

        let count = min(matchResults.count, min(weights.count, durations.count))
        for index in 0..<count {
            let weight = weights[index]
            guard weight.isFinite, weight > 0 else { continue }

            eligibleSegmentCount += 1
            totalWeight += weight

            guard let match = matchResults[index],
                  match.profileID == aggregateMatch.profileID else {
                continue
            }

            agreeingWeight += weight
            if durations[index] >= Self.identityLongSegmentDurationSeconds {
                hasLongAgreeingSegment = true
            }
        }

        if hasLongAgreeingSegment {
            return true
        }

        guard eligibleSegmentCount >= 2,
              totalWeight.isFinite,
              totalWeight > 0 else {
            return false
        }

        return (agreeingWeight / totalWeight) >= Self.identityConsensusWeightRatio
    }

    private func validEmbedding(_ embedding: [Float]?) -> [Float]? {
        guard let embedding, !embedding.isEmpty else { return nil }
        guard embedding.allSatisfy(\.isFinite) else { return nil }
        return embedding
    }

    private func splitTranscriptSegmentIfNeeded(
        _ segment: DiarizedTranscriptSegment
    ) -> [DiarizedTranscriptSegment] {
        let duration = max(segment.endTime - segment.startTime, 0)
        let totalWords = wordCount(in: segment.text)

        guard duration > Self.maximumTranscriptChunkDurationSeconds ||
                totalWords > Self.maximumTranscriptChunkWordCount else {
            return [segment]
        }

        let textualUnits = transcriptTextUnits(from: segment.text)
        guard textualUnits.count > 1 || totalWords > Self.maximumTranscriptChunkWordCount else {
            return [segment]
        }

        let chunkTexts = packedTranscriptChunks(from: textualUnits)
        guard chunkTexts.count > 1 else {
            return [segment]
        }

        let weightedChunkWordCounts = chunkTexts.map { max(1, wordCount(in: $0)) }
        let totalWeightedWords = max(1, weightedChunkWordCounts.reduce(0, +))

        var splitSegments: [DiarizedTranscriptSegment] = []
        splitSegments.reserveCapacity(chunkTexts.count)

        var chunkStart = segment.startTime

        for (index, chunkText) in chunkTexts.enumerated() {
            let chunkEnd: TimeInterval
            if index == chunkTexts.count - 1 {
                chunkEnd = segment.endTime
            } else {
                let proportionalDuration = duration * (Double(weightedChunkWordCounts[index]) / Double(totalWeightedWords))
                chunkEnd = min(segment.endTime, max(chunkStart, chunkStart + proportionalDuration))
            }

            splitSegments.append(
                DiarizedTranscriptSegment(
                    speakerId: segment.speakerId,
                    speakerLabel: segment.speakerLabel,
                    speakerProfileID: segment.speakerProfileID,
                    speakerEmbedding: segment.speakerEmbedding,
                    startTime: chunkStart,
                    endTime: chunkEnd,
                    confidence: segment.confidence,
                    text: chunkText
                )
            )
            chunkStart = chunkEnd
        }

        return splitSegments
    }

    private func transcriptTextUnits(from text: String) -> [String] {
        let sentenceUnits = sentenceUnits(from: text)
        let baseUnits = sentenceUnits.isEmpty ? [text] : sentenceUnits

        return baseUnits.flatMap { sentence in
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSentence.isEmpty else { return [String]() }

            if wordCount(in: trimmedSentence) <= Self.maximumTranscriptChunkWordCount {
                return [trimmedSentence]
            }

            return splitTextByWordCount(trimmedSentence, maximumWords: Self.targetTranscriptChunkWordCount)
        }
    }

    private func sentenceUnits(from text: String) -> [String] {
        let nsText = text as NSString
        var units: [String] = []

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            guard range.location != NSNotFound else { return }
            let sentence = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return }
            units.append(sentence)
        }

        return units
    }

    private func packedTranscriptChunks(from units: [String]) -> [String] {
        guard !units.isEmpty else { return [] }

        var chunks: [String] = []
        var currentUnits: [String] = []
        var currentWordCount = 0

        for unit in units {
            let unitWordCount = max(1, wordCount(in: unit))
            let exceedsWordLimit = !currentUnits.isEmpty &&
                (currentWordCount + unitWordCount) > Self.maximumTranscriptChunkWordCount

            if exceedsWordLimit {
                chunks.append(currentUnits.joined(separator: " "))
                currentUnits = [unit]
                currentWordCount = unitWordCount
                continue
            }

            currentUnits.append(unit)
            currentWordCount += unitWordCount
        }

        if !currentUnits.isEmpty {
            chunks.append(currentUnits.joined(separator: " "))
        }

        return chunks
    }

    private func splitTextByWordCount(_ text: String, maximumWords: Int) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        var startIndex = 0

        while startIndex < words.count {
            let endIndex = min(startIndex + maximumWords, words.count)
            let chunk = words[startIndex..<endIndex].joined(separator: " ")
            chunks.append(chunk)
            startIndex = endIndex
        }

        return chunks
    }

    private func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func normalizedDiarizationSegments(
        _ segments: [PindropCore.SpeakerSegment],
        audioDuration: TimeInterval
    ) -> [PindropCore.SpeakerSegment] {
        let clampedSegments: [PindropCore.SpeakerSegment] = segments
            .compactMap { segment in
                let start = max(0, min(segment.startTime, audioDuration))
                let end = max(0, min(segment.endTime, audioDuration))
                guard end > start else { return nil }
                let confidence = segment.confidence.isFinite
                    ? min(max(segment.confidence, 0), 1)
                    : 0
                return PindropCore.SpeakerSegment(
                    speaker: segment.speaker,
                    startTime: start,
                    endTime: end,
                    confidence: confidence
                )
            }
            .sorted { $0.startTime < $1.startTime }

        guard !clampedSegments.isEmpty else { return [] }

        var mergedSegments: [PindropCore.SpeakerSegment] = []
        mergedSegments.reserveCapacity(clampedSegments.count)

        for segment in clampedSegments {
            guard let previous = mergedSegments.last else {
                mergedSegments.append(segment)
                continue
            }

            let gap = segment.startTime - previous.endTime
            let sameSpeaker = previous.speaker.id == segment.speaker.id

            // Only merge identical ephemeral IDs within the gap budget.
            if sameSpeaker && gap <= Self.diarizationMergeGapSeconds {
                let previousDuration = max(previous.duration, 0)
                let currentDuration = max(segment.duration, 0)
                let combinedDuration = previousDuration + currentDuration
                let weightedConfidence: Float
                if combinedDuration > 0 {
                    weightedConfidence = (
                        previous.confidence * Float(previousDuration) +
                        segment.confidence * Float(currentDuration)
                    ) / Float(combinedDuration)
                } else {
                    weightedConfidence = (previous.confidence + segment.confidence) / 2
                }

                let mergedEmbedding = durationWeightedEmbedding(
                    lhs: previous.speaker.embedding,
                    lhsDuration: previousDuration,
                    rhs: segment.speaker.embedding,
                    rhsDuration: currentDuration
                )

                let mergedSpeaker = PindropCore.Speaker(
                    id: previous.speaker.id,
                    label: previous.speaker.label,
                    embedding: mergedEmbedding
                )

                let merged = PindropCore.SpeakerSegment(
                    speaker: mergedSpeaker,
                    startTime: previous.startTime,
                    endTime: max(previous.endTime, segment.endTime),
                    confidence: weightedConfidence
                )

                mergedSegments[mergedSegments.count - 1] = merged
            } else {
                mergedSegments.append(segment)
            }
        }

        return mergedSegments
    }

    private func durationWeightedEmbedding(
        lhs: [Float]?,
        lhsDuration: TimeInterval,
        rhs: [Float]?,
        rhsDuration: TimeInterval
    ) -> [Float]? {
        let left = validEmbedding(lhs)
        let right = validEmbedding(rhs)

        switch (left, right) {
        case let (left?, right?) where left.count == right.count:
            let leftWeight = Float(max(lhsDuration, 0))
            let rightWeight = Float(max(rhsDuration, 0))
            let totalWeight = leftWeight + rightWeight
            if totalWeight > 0 {
                return zip(left, right).map { leftValue, rightValue in
                    ((leftValue * leftWeight) + (rightValue * rightWeight)) / totalWeight
                }
            }
            return zip(left, right).map { ($0 + $1) / 2 }
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return left ?? right
        }
    }

    private func extractAudioData(
        samples: [Float],
        sampleRate: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        previousEndTime: TimeInterval? = nil,
        nextStartTime: TimeInterval? = nil
    ) -> Data? {
        guard sampleRate > 0, !samples.isEmpty else { return nil }
        guard endTime > startTime else { return nil }

        let audioDuration = Double(samples.count) / Double(sampleRate)

        // Pad up to 150 ms of context on each side, clamped to recording bounds
        // and the midpoint of any gap to the adjacent segment. No padding across
        // overlapping or abutting neighbors.
        var paddedStart = max(0, startTime - Self.segmentContextPaddingSeconds)
        if let previousEndTime {
            if previousEndTime >= startTime {
                paddedStart = startTime
            } else {
                let midpoint = (previousEndTime + startTime) / 2
                paddedStart = max(paddedStart, midpoint)
            }
        }

        var paddedEnd = min(audioDuration, endTime + Self.segmentContextPaddingSeconds)
        if let nextStartTime {
            if nextStartTime <= endTime {
                paddedEnd = endTime
            } else {
                let midpoint = (endTime + nextStartTime) / 2
                paddedEnd = min(paddedEnd, midpoint)
            }
        }

        paddedStart = max(0, min(paddedStart, audioDuration))
        paddedEnd = max(paddedStart, min(paddedEnd, audioDuration))
        guard paddedEnd > paddedStart else { return nil }

        let startIndex = max(0, min(samples.count - 1, Int((paddedStart * Double(sampleRate)).rounded(.down))))
        let endIndex = max(startIndex + 1, min(samples.count, Int((paddedEnd * Double(sampleRate)).rounded(.up))))
        guard endIndex > startIndex else { return nil }

        return samples.withUnsafeBufferPointer { samplesBuffer in
            let slice = UnsafeBufferPointer(rebasing: samplesBuffer[startIndex..<endIndex])
            return Data(buffer: slice)
        }
    }

    private func getOrCreateSpeakerDiarizer() -> any SpeakerDiarizer {
        if let speakerDiarizer {
            return speakerDiarizer
        }

        let created = speakerDiarizerFactory(storageLocations.fluidAudioModelsRoot)
        speakerDiarizer = created
        return created
    }

    private func validateExpectedSpeakerCount(_ expectedSpeakerCount: Int?) throws {
        guard let expectedSpeakerCount else { return }
        guard (1...20).contains(expectedSpeakerCount) else {
            throw TranscriptionError.diarizationFailed(
                "Expected speaker count must be between 1 and 20."
            )
        }
    }

    private func logDiarizationDiagnostics(
        requestedSpeakerCount: Int?,
        observedSpeakerCount: Int,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        let requestedDescription = requestedSpeakerCount.map(String.init) ?? "automatic"
        Log.transcription.info(
            "Diarization pipeline=offline-community1 requestedSpeakers=\(requestedDescription) observedSpeakers=\(observedSpeakerCount) audioDuration=\(String(format: "%.2f", audioDuration))s processingDuration=\(String(format: "%.2f", processingDuration))s clusteringThreshold=\(String(format: "%.2f", Self.offlineCommunity1ClusteringThreshold))"
        )
    }

    private static func defaultEngineFactory(
        provider: ModelManager.ModelProvider
    ) throws -> any TranscriptionEngine {
        switch provider {
        case .whisperKit:
            return WhisperKitEngine()
        case .parakeet:
            return ParakeetEngine()
        case .senseVoice:
            return SenseVoiceEngine()
        case .appleSpeech:
            return AppleSpeechEngine()
        default:
            throw TranscriptionError.modelLoadFailed("Provider \(provider.rawValue) not supported locally")
        }
    }

    /// Provider-specific model root derived from injected storage locations.
    /// Never reconstructs Application Support defaults.
    private func downloadBase(
        for provider: ModelManager.ModelProvider,
        modelName: String
    ) -> URL? {
        switch provider {
        case .whisperKit:
            return storageLocations.pindropApplicationSupportRoot
        case .parakeet:
            return ParakeetEngine.modelDirectory(
                forName: modelName,
                fluidAudioModelsRoot: storageLocations.fluidAudioModelsRoot
            )
        case .senseVoice:
            return storageLocations.fluidAudioModelsRoot
                .appendingPathComponent(Repo.senseVoiceSmall.folderName, isDirectory: true)
        case .appleSpeech, .openAI, .elevenLabs, .groq:
            return nil
        }
    }

    private func loadModelWithOptionalWatchdog(
        operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        guard let modelLoadTimeoutSeconds else {
            try await operation()
            return
        }

        try await withAsyncWatchdog(
            timeoutSeconds: modelLoadTimeoutSeconds,
            timeoutError: { Self.modelLoadTimeoutError(after: modelLoadTimeoutSeconds) },
            operation: operation
        )
    }

    private nonisolated static func modelLoadTimeoutError(after timeoutSeconds: TimeInterval) -> TranscriptionError {
        .modelLoadFailed(
            "Model loading timed out after \(Int(timeoutSeconds))s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings."
        )
    }

    /// Installs the stable engine→delivery bridge once per engine instance.
    /// Must complete before `loadModel` / `startStreaming` so emissions cannot
    /// land before sinks are wired. Sink changes go through `setStreamingCallbacks`
    /// and are picked up live by these callbacks — do not reinstall on sink updates.
    private func callbackSource(
        for streamingEngine: any StreamingTranscriptionEngine,
        lifecycleEpoch: UInt64
    ) async throws -> StreamingCallbackDelivery.Source {
        let identity = ObjectIdentifier(streamingEngine)
        if let bridge = streamingCallbackBridges[identity],
           bridge.engine === (streamingEngine as AnyObject) {
            streamingCallbackDelivery.activate(bridge.source)
            return bridge.source
        }
        streamingCallbackBridges.removeValue(forKey: identity)

        // Finish both invariant setter awaits before publishing the bridge record.
        // The adoption lease prevents a stale installation from overlapping a
        // newer owner of the same concrete engine object.
        let delivery = streamingCallbackDelivery
        let source = delivery.makeSource()
        await streamingEngine.setTranscriptionCallback { result in
            guard !result.isFinal else { return }
            let emission = StreamingTranscriptionEmission(
                text: result.text,
                fedSeconds: result.fedSeconds
            )
            guard let generation = delivery.enqueuePartial(emission, from: source) else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.drainStreamingCallbackDelivery(generation: generation)
            }
        }
        await streamingEngine.setEndOfUtteranceCallback { emission in
            guard let generation = delivery.enqueueFinal(emission, from: source) else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.drainStreamingCallbackDelivery(generation: generation)
            }
        }
        streamingCallbackBridges[identity] = StreamingCallbackBridge(
            engine: streamingEngine,
            source: source
        )
        guard lifecycleEpoch == streamingLifecycleEpoch else {
            delivery.invalidateSource(source)
            throw CancellationError()
        }
        return source
    }

    private func drainStreamingCallbackDelivery(generation: UInt64) async {
        while true {
            let events = streamingCallbackDelivery.snapshotAndClear(forGeneration: generation)
            eventLoop: for event in events {
                // Capture sinks only while this generation is still current so a
                // concurrent reset cannot redirect snapshotted events into the
                // next session. In-flight awaits keep the captured old sink.
                guard streamingCallbackDelivery.isCurrentGeneration(generation) else {
                    break eventLoop
                }
                switch event {
                case .partial(let emission):
                    let callback = streamingPartialCallback
                    guard streamingCallbackDelivery.isCurrentGeneration(generation) else {
                        break eventLoop
                    }
                    await callback?(emission)
                case .final(let emission):
                    let callback = streamingFinalUtteranceCallback
                    guard streamingCallbackDelivery.isCurrentGeneration(generation) else {
                        break eventLoop
                    }
                    await callback?(emission)
                }
            }

            switch streamingCallbackDelivery.completeDrain(forGeneration: generation) {
            case .continueDrain:
                continue
            case .finished:
                return
            }
        }
    }

    /// Converts PCM float32 `Data` into a sample array using a bulk copy.
    /// Runs off the main actor so large captures do not stall UI work.
    nonisolated private static func floatSamples(from data: Data) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            Self.dataToFloatArray(data)
        }.value
    }

    nonisolated private static func dataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return [] }

        return data.withUnsafeBytes { rawBuffer -> [Float] in
            guard let baseAddress = rawBuffer.baseAddress else { return [] }
            let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
            // Bulk-initialize from the source buffer; avoid zero-fill then overwrite.
            return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
        }
    }
}

/// Bridges nonisolated streaming-engine callbacks onto the main actor with a
/// single isolation hop. Consecutive partials collapse to the latest value;
/// final utterances are queued in arrival order and never dropped.
///
/// Ownership is serialized within one delivery generation. Invalidation releases
/// the next generation immediately, so a suspended stale sink cannot starve the
/// replacement session. When that stale drain resumes, its generation mismatch
/// makes it exit without reading or clearing the current queue/owner.
private final class StreamingCallbackDelivery: @unchecked Sendable {
    final class Source: @unchecked Sendable {
        fileprivate let id: UInt64

        fileprivate init(id: UInt64) {
            self.id = id
        }
    }

    enum Event: Sendable {
        case partial(StreamingTranscriptionEmission)
        case final(StreamingTranscriptionEmission)
    }

    enum DrainPoll: Sendable {
        /// Same generation still has queued work.
        case continueDrain
        /// This drain released ownership or was superseded; caller must exit.
        case finished
    }

    private let lock = NSLock()
    private var generation: UInt64 = 1
    private var nextSourceID: UInt64 = 1
    private var activeSourceID: UInt64?
    private var queue: [Event] = []
    /// Generation that owns its serialized drain task, if any.
    private var drainOwnerGeneration: UInt64?

    /// Creates and activates the token captured by one engine callback bridge.
    func makeSource() -> Source {
        lock.lock()
        defer { lock.unlock() }
        let source = Source(id: nextSourceID)
        nextSourceID &+= 1
        activeSourceID = source.id
        advanceGenerationAndClearQueue()
        return source
    }

    /// Reactivates the existing bridge after a completed engine reset.
    func activate(_ source: Source) {
        lock.lock()
        defer { lock.unlock() }
        guard activeSourceID != source.id else { return }
        activeSourceID = source.id
        advanceGenerationAndClearQueue()
    }

    /// Invalidates only this source. A stale source cannot deactivate its replacement.
    func invalidateSource(_ source: Source?) {
        lock.lock()
        defer { lock.unlock() }
        guard let source, activeSourceID == source.id else { return }
        activeSourceID = nil
        advanceGenerationAndClearQueue()
    }

    /// Lifecycle teardown also fences a source whose installation has suspended
    /// before the main-actor service records its token.
    func invalidateCurrentSource() {
        lock.lock()
        activeSourceID = nil
        advanceGenerationAndClearQueue()
        lock.unlock()
    }

    /// Enqueue a partial. Returns a generation when the caller must start the drain.
    ///
    /// Replacing the queued partial wholesale is what keeps the fed watermark
    /// honest: the survivor carries its own watermark, never an older one.
    func enqueuePartial(_ emission: StreamingTranscriptionEmission, from source: Source) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard activeSourceID == source.id else { return nil }
        if let lastIndex = queue.indices.last, case .partial = queue[lastIndex] {
            queue[lastIndex] = .partial(emission)
        } else {
            queue.append(.partial(emission))
        }
        return claimDrainIfIdle()
    }

    /// Enqueue a final utterance. Returns a generation when the caller must start the drain.
    func enqueueFinal(_ emission: StreamingTranscriptionEmission, from source: Source) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard activeSourceID == source.id else { return nil }
        queue.append(.final(emission))
        return claimDrainIfIdle()
    }

    func isCurrentGeneration(_ expected: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return expected == generation
    }

    func snapshotAndClear(forGeneration expected: UInt64) -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        guard expected == generation else { return [] }
        let events = queue
        queue.removeAll(keepingCapacity: true)
        return events
    }

    /// Called by a generation's drain after each batch. A stale generation never
    /// mutates current ownership; a current drain retains ownership while work remains.
    func completeDrain(forGeneration expected: UInt64) -> DrainPoll {
        lock.lock()
        defer { lock.unlock() }

        // Invalidation already released this generation's ownership. A stale
        // drain must not inspect, adopt, or clear the replacement owner/queue.
        guard expected == generation else {
            return .finished
        }
        if !queue.isEmpty {
            return .continueDrain
        }
        if drainOwnerGeneration == expected {
            drainOwnerGeneration = nil
        }
        return .finished
    }

    func reset() {
        lock.lock()
        advanceGenerationAndClearQueue()
        lock.unlock()
    }

    private func advanceGenerationAndClearQueue() {
        generation &+= 1
        queue.removeAll(keepingCapacity: false)
        // Drain ownership is generation-scoped. The stale task may remain
        // suspended, but current events can now claim their own drain.
        drainOwnerGeneration = nil
    }

    private func claimDrainIfIdle() -> UInt64? {
        if drainOwnerGeneration != nil {
            return nil
        }
        drainOwnerGeneration = generation
        return generation
    }
}

private struct DiarizationTimeoutError: Error, LocalizedError {
    let timeoutSeconds: TimeInterval

    var errorDescription: String? {
        "Speaker diarization timed out after \(Int(timeoutSeconds)) seconds."
    }
}

private final class AsyncOneShotState<Output>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingResult: Result<Output, Error>?
    private var isResolved = false

    func activate(_ continuation: CheckedContinuation<Output, Error>) -> Bool {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
            return false
        }

        if isResolved {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }

        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = isResolved
        if !shouldCancel {
            operationTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = isResolved
        if !shouldCancel {
            timeoutTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func resolve(_ result: Result<Output, Error>) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }

        isResolved = true
        let continuationToResume = continuation
        continuation = nil
        let operationTaskToCancel = operationTask
        operationTask = nil
        let timeoutTaskToCancel = timeoutTask
        timeoutTask = nil

        if continuationToResume == nil {
            pendingResult = result
        }
        lock.unlock()

        operationTaskToCancel?.cancel()
        timeoutTaskToCancel?.cancel()
        continuationToResume?.resume(with: result)
    }
}

private func withPromptCancellation<Output>(
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    let state = AsyncOneShotState<Output>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard state.activate(continuation) else { return }

            if Task.isCancelled {
                state.resolve(.failure(CancellationError()))
                return
            }

            let operationTask = Task.detached {
                do {
                    state.resolve(.success(try await operation()))
                } catch {
                    state.resolve(.failure(error))
                }
            }
            state.setOperationTask(operationTask)
        }
    } onCancel: {
        state.resolve(.failure(CancellationError()))
    }
}

@MainActor
private func withAsyncWatchdog<Output>(
    timeoutSeconds: TimeInterval,
    timeoutError: @escaping @Sendable () -> Error,
    operation: @escaping @MainActor () async throws -> Output
) async throws -> Output {
    let state = AsyncOneShotState<Output>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard state.activate(continuation) else { return }

            if Task.isCancelled {
                state.resolve(.failure(CancellationError()))
                return
            }

            let operationTask = Task.detached { @MainActor in
                do {
                    state.resolve(.success(try await operation()))
                } catch {
                    state.resolve(.failure(error))
                }
            }
            state.setOperationTask(operationTask)

            let timeoutTask = Task.detached {
                let clampedTimeout = max(timeoutSeconds, 0)
                let nanoseconds = UInt64(clampedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                state.resolve(.failure(timeoutError()))
            }
            state.setTimeoutTask(timeoutTask)
        }
    } onCancel: {
        state.resolve(.failure(CancellationError()))
    }
}
