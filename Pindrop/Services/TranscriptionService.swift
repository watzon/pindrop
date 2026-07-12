//
//  TranscriptionService.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import AVFoundation
import Foundation
import os.log

@MainActor
@Observable
class TranscriptionService {

    enum State: Equatable {
        case unloaded
        case loading
        case ready
        case transcribing
        case error
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case invalidAudioData
        case transcriptionFailed(String)
        case modelLoadFailed(String)
        case engineSwitchDuringTranscription
        case streamingModelNotAvailable(String)
        case streamingNotReady
        case streamingStartFailed(String)
        case streamingProcessingFailed(String)
        case streamingStopFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Model not loaded. Call loadModel() first."
            case .invalidAudioData:
                return "Invalid audio data. Expected 16kHz mono PCM format."
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .modelLoadFailed(let message):
                return "Model load failed: \(message)"
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
    private static let diarizationMergeGapSeconds: TimeInterval = 0.30
    private static let minimumSegmentDurationSeconds: TimeInterval = 1.0
    private static let maximumTranscriptChunkDurationSeconds: TimeInterval = 12.0
    private static let maximumTranscriptChunkWordCount = 28
    private static let targetTranscriptChunkWordCount = 20
    private static let defaultDiarizationTimeoutSeconds: TimeInterval = 300
    private static let defaultModelLoadTimeoutSeconds: TimeInterval = 120

    private(set) var state: State = .unloaded
    private(set) var error: Error?
    private var engine: (any TranscriptionEngine)?
    private var speakerDiarizer: (any SpeakerDiarizer)?
    private var streamingEngine: (any StreamingTranscriptionEngine)?

    /// The live engine for the streaming session's audio pump. The pump runs on a
    /// detached task and calls the engine directly — routing each buffer through
    /// this @MainActor service would re-serialize decode behind UI work.
    var activeStreamingEngine: (any StreamingTranscriptionEngine)? { streamingEngine }
    /// In-flight streaming-engine preparation, shared by concurrent callers so a
    /// session starting during the launch prewarm awaits the same load instead of
    /// hitting the engine's `.loading` state and falling back to batch. Class
    /// wrapper so callers can identity-check before clearing the slot.
    private final class StreamingPrepareHandle {
        let task: Task<Void, Error>
        init(task: Task<Void, Error>) { self.task = task }
    }
    private var streamingPrepareHandle: StreamingPrepareHandle?
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
    private var streamingPartialCallback: (@Sendable (String) -> Void)?
    private var streamingFinalUtteranceCallback: (@Sendable (String) -> Void)?

    private let engineFactory: @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine
    private let speakerDiarizerFactory: @MainActor () -> any SpeakerDiarizer
    private let streamingEngineFactory: @MainActor (StreamingChunkProfile) -> any StreamingTranscriptionEngine
    private let appleSpeechEngineFactory: @MainActor () -> (any StreamingTranscriptionEngine)?
    private var streamingChunkProfileProvider: @MainActor () -> StreamingChunkProfile
    private var streamingBackendProvider: @MainActor () -> TranscriptionBackend
    private let speakerIdentityService: SpeakerIdentityManaging?
    private let diarizationTimeoutSeconds: TimeInterval?
    private let modelLoadTimeoutSeconds: TimeInterval

    /// True once this service substituted Parakeet for a user-requested Apple backend
    /// that couldn't be provisioned this run. AppCoordinator reads it to surface a
    /// one-time toast. Consumed and reset by `consumeAppleBackendFallbackFlag()`.
    private(set) var appleBackendFellBackToParakeet: Bool = false

    init(
        engineFactory: @escaping @MainActor (ModelManager.ModelProvider) throws -> any TranscriptionEngine = {
            try TranscriptionService.defaultEngineFactory(provider: $0)
        },
        diarizerFactory: @escaping @MainActor () -> any SpeakerDiarizer = {
            FluidSpeakerDiarizer()
        },
        streamingEngineFactory: @escaping @MainActor (StreamingChunkProfile) -> any StreamingTranscriptionEngine = {
            NemotronStreamingEngine(chunkProfile: $0)
        },
        appleSpeechEngineFactory: @escaping @MainActor () -> (any StreamingTranscriptionEngine)? = {
            if #available(macOS 26, *) {
                return AppleSpeechTranscriberEngine()
            }
            return nil
        },
        streamingChunkProfileProvider: @escaping @MainActor () -> StreamingChunkProfile = { .standard },
        streamingBackendProvider: @escaping @MainActor () -> TranscriptionBackend = { .parakeet },
        speakerIdentityService: SpeakerIdentityManaging? = nil,
        diarizationTimeoutSeconds: TimeInterval? = TranscriptionService.defaultDiarizationTimeoutSeconds,
        modelLoadTimeoutSeconds: TimeInterval = TranscriptionService.defaultModelLoadTimeoutSeconds
    ) {
        self.engineFactory = engineFactory
        self.speakerDiarizerFactory = diarizerFactory
        self.streamingEngineFactory = streamingEngineFactory
        self.appleSpeechEngineFactory = appleSpeechEngineFactory
        self.streamingChunkProfileProvider = streamingChunkProfileProvider
        self.streamingBackendProvider = streamingBackendProvider
        self.speakerIdentityService = speakerIdentityService
        self.diarizationTimeoutSeconds = diarizationTimeoutSeconds
        self.modelLoadTimeoutSeconds = modelLoadTimeoutSeconds
    }

    /// Replace the provider that resolves which streaming chunk profile to use. Safe to
    /// call post-init (AppCoordinator composes the TranscriptionService before the
    /// SettingsStore exists in its own init ordering).
    func setStreamingChunkProfileProvider(_ provider: @escaping @MainActor () -> StreamingChunkProfile) {
        self.streamingChunkProfileProvider = provider
    }

    /// Replace the provider that resolves which streaming backend to use (Parakeet vs
    /// Apple SpeechTranscriber).
    func setStreamingBackendProvider(_ provider: @escaping @MainActor () -> TranscriptionBackend) {
        self.streamingBackendProvider = provider
    }

    /// Read-and-clear the Apple fallback flag. Returns true exactly once after a
    /// fallback happens.
    func consumeAppleBackendFallbackFlag() -> Bool {
        let value = appleBackendFellBackToParakeet
        appleBackendFellBackToParakeet = false
        return value
    }

    func loadModel(modelName: String = "tiny", provider: ModelManager.ModelProvider = .whisperKit) async throws {
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
            let newEngine = try engineFactory(provider)
            let modelLoadTimeoutSeconds = self.modelLoadTimeoutSeconds
            Log.boot.info("TranscriptionService.loadModel engine instance created provider=\(provider.rawValue) elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")

            try await withAsyncWatchdog(
                timeoutSeconds: modelLoadTimeoutSeconds,
                timeoutError: { Self.modelLoadTimeoutError(after: modelLoadTimeoutSeconds) }
            ) {
                Log.boot.info("TranscriptionService.loadModel engine.loadModel task started name=\(modelName)")
                let engineLoadStart = CFAbsoluteTimeGetCurrent()
                try await newEngine.loadModel(name: modelName, downloadBase: self.getDownloadBase())
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

    func loadModel(modelPath: String) async throws {
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
            let modelLoadTimeoutSeconds = self.modelLoadTimeoutSeconds
            Log.boot.info("TranscriptionService.loadModel(path) WhisperKitEngine created elapsed=\(String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - loadStarted))")

            try await withAsyncWatchdog(
                timeoutSeconds: modelLoadTimeoutSeconds,
                timeoutError: { Self.modelLoadTimeoutError(after: modelLoadTimeoutSeconds) }
            ) {
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

    func transcribe(audioData: Data) async throws -> String {
        try await transcribe(audioData: audioData, options: TranscriptionOptions())
    }

    func transcribe(audioData: Data, options: TranscriptionOptions) async throws -> String {
        try await transcribe(audioData: audioData, diarizationEnabled: false, options: options).text
    }

    func transcribe(audioData: Data, diarizationEnabled: Bool) async throws -> TranscriptionOutput {
        try await transcribe(
            audioData: audioData,
            diarizationEnabled: diarizationEnabled,
            options: TranscriptionOptions()
        )
    }

    func transcribe(
        audioData: Data,
        diarizationEnabled: Bool,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        Log.transcription.debug("Transcribe called with \(audioData.count) bytes, state: \(String(describing: self.state))")

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
            let floatCount = audioData.count / MemoryLayout<Float>.size
            let duration = Double(floatCount) / Double(Self.sampleRate)
            let providerName = currentProvider?.rawValue ?? "unknown"
            Log.transcription.info("Transcribing \(floatCount) samples (\(String(format: "%.2f", duration))s) using \(providerName)")

            let startTime = Date()
            let samples = dataToFloatArray(audioData)

            let output = try await transcribeWithOptionalDiarization(
                engine: engine,
                audioData: audioData,
                samples: samples,
                sampleRate: Self.sampleRate,
                diarizationEnabled: diarizationEnabled,
                options: options
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

    /// Called by a hard deadline after it has cancelled a batch operation. The
    /// previous engine may still be executing and is never touched concurrently;
    /// dropping it forces the next batch operation to load a distinct engine.
    func invalidateTimedOutTranscription() {
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

    func extractSpeakerProfileSegments(audioData: Data) async throws -> [DiarizedTranscriptSegment] {
        guard !audioData.isEmpty else {
            throw TranscriptionError.invalidAudioData
        }

        let samples = dataToFloatArray(audioData)
        let diarizer = try await prepareSpeakerDiarizer()
        try await diarizer.loadModels()
        let result = try await diarizeWithWatchdog(
            diarizer: diarizer,
            samples: samples,
            sampleRate: Self.sampleRate
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

    func unloadModel() async {
        await engine?.unloadModel()
        await speakerDiarizer?.unloadModels()
        await streamingEngine?.unloadModel()
        engine = nil
        speakerDiarizer = nil
        streamingEngine = nil
        currentProvider = nil
        batchModelIdentity = nil
        state = .unloaded
        error = nil
    }

    func setStreamingCallbacks(
        onPartial: (@Sendable (String) -> Void)? = nil,
        onFinalUtterance: (@Sendable (String) -> Void)? = nil
    ) {
        streamingPartialCallback = onPartial
        streamingFinalUtteranceCallback = onFinalUtterance
        applyStreamingCallbacks()
    }

    func prepareStreamingEngine() async throws {
        // Wait out any in-flight preparation, then reconcile once more against
        // the settings as they are NOW — a caller landing mid-prewarm must not
        // inherit the backend/chunk profile captured when that prepare started.
        // The re-run is a cheap early-return when nothing changed. Errors from
        // the in-flight task are ignored here; our own run rethrows fresh ones.
        while let inFlight = streamingPrepareHandle {
            _ = try? await inFlight.task.value
            if streamingPrepareHandle === inFlight { streamingPrepareHandle = nil }
        }
        let task = Task { try await performPrepareStreamingEngine() }
        let handle = StreamingPrepareHandle(task: task)
        streamingPrepareHandle = handle
        defer { if streamingPrepareHandle === handle { streamingPrepareHandle = nil } }
        try await task.value
    }

    private func performPrepareStreamingEngine() async throws {
        let profile = streamingChunkProfileProvider()
        let requestedBackend = streamingBackendProvider()

        // Resolve the backend we can actually run. Apple's SpeechTranscriber only exists
        // on macOS 26+; on older hosts fall back to Parakeet and remember to surface a
        // toast to the user.
        let effectiveBackend: TranscriptionBackend
        if requestedBackend == .appleSpeechTranscriber, appleSpeechEngineFactory() == nil {
            effectiveBackend = .parakeet
            appleBackendFellBackToParakeet = true
            Log.transcription.warning(
                "Apple SpeechTranscriber requested but unavailable on this host; falling back to Nemotron"
            )
        } else {
            effectiveBackend = requestedBackend
        }

        // Recreate the engine when the backend changes or, for Parakeet, when the chunk
        // profile changes.
        if let existing = streamingEngine {
            let existingBackend = Self.backendFor(engine: existing)
            var recreate = existingBackend != effectiveBackend
            if !recreate, effectiveBackend == .parakeet,
               let nemotron = existing as? NemotronStreamingEngine {
                if await nemotron.chunkProfile != profile {
                    await nemotron.updateChunkProfile(profile)
                    recreate = true
                }
            }
            if recreate {
                await existing.unloadModel()
                streamingEngine = nil
            }
        }

        if streamingEngine == nil {
            let created: any StreamingTranscriptionEngine
            switch effectiveBackend {
            case .parakeet:
                created = streamingEngineFactory(profile)
            case .appleSpeechTranscriber:
                guard let apple = appleSpeechEngineFactory() else {
                    // Shouldn't happen — handled above — but stay defensive.
                    appleBackendFellBackToParakeet = true
                    created = streamingEngineFactory(profile)
                    break
                }
                created = apple
            }
            streamingEngine = created
            applyStreamingCallbacks()
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        switch await streamingEngine.state {
        case .ready, .streaming, .paused:
            if state == .unloaded || state == .error {
                state = .ready
            }
            return
        case .loading:
            return
        case .unloaded, .error:
            break
        }

        // Model path is only relevant for Parakeet; the Apple engine ignores `name`.
        let modelPath: String
        switch effectiveBackend {
        case .parakeet:
            modelPath = FeatureModelType.streamingRepoFolderName(for: profile)
        case .appleSpeechTranscriber:
            modelPath = ""
        }
        do {
            try await streamingEngine.loadModel(name: modelPath)
            if state == .unloaded || state == .error {
                state = .ready
            }
        } catch {
            let streamingError: TranscriptionError
            switch effectiveBackend {
            case .parakeet:
                let path = getStreamingModelBase()
                    .appendingPathComponent(modelPath, isDirectory: true)
                    .path
                streamingError = TranscriptionError.streamingModelNotAvailable(path)
            case .appleSpeechTranscriber:
                streamingError = TranscriptionError.streamingStartFailed(
                    error.localizedDescription)
            }
            self.error = streamingError
            // A streaming-prepare failure (reachable from the background prewarm
            // at any time) must not clobber the batch engine's state machine —
            // mirror the guarded success path above.
            if state == .unloaded || state == .error {
                state = .error
            }
            throw streamingError
        }
    }

    /// Map an existing engine instance back to the `TranscriptionBackend` that produced it.
    private static func backendFor(engine: any StreamingTranscriptionEngine) -> TranscriptionBackend {
        if engine is NemotronStreamingEngine {
            return .parakeet
        }
        if #available(macOS 26, *) {
            if engine is AppleSpeechTranscriberEngine {
                return .appleSpeechTranscriber
            }
        }
        return .parakeet
    }

    func startStreaming() async throws {
        guard state != .transcribing else {
            throw TranscriptionError.transcriptionFailed("Transcription already in progress")
        }

        do {
            try await prepareStreamingEngine()
            guard let streamingEngine else {
                throw TranscriptionError.streamingNotReady
            }
            try await streamingEngine.startStreaming()
            state = .transcribing
            error = nil
        } catch let error as TranscriptionError {
            self.error = error
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStartFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func processStreamingAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard state == .transcribing else {
            throw TranscriptionError.streamingNotReady
        }

        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            try await streamingEngine.processAudioBuffer(buffer)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingProcessingFailed(error.localizedDescription)
            self.error = streamingError
            throw streamingError
        }
    }

    func stopStreaming() async throws -> String {
        guard let streamingEngine else {
            throw TranscriptionError.streamingNotReady
        }

        do {
            let finalText = try await streamingEngine.stopStreaming()
            state = .ready
            return finalText
        } catch let error as TranscriptionError {
            state = .ready
            throw error
        } catch {
            let streamingError = TranscriptionError.streamingStopFailed(error.localizedDescription)
            self.error = streamingError
            state = .ready
            throw streamingError
        }
    }

    func cancelStreaming() async {
        await streamingEngine?.reset()
        if engine != nil || streamingEngine != nil {
            state = .ready
        } else {
            state = .unloaded
        }
    }

    private func transcribeWithOptionalDiarization(
        engine: any TranscriptionEngine,
        audioData: Data,
        samples: [Float],
        sampleRate: Int,
        diarizationEnabled: Bool,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        guard diarizationEnabled else {
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData, options: options)
        }

        Log.transcription.info("Speaker diarization enabled for current transcription")

        do {
            try Task.checkCancellation()
            let diarizer = try await prepareSpeakerDiarizer()
            try Task.checkCancellation()
            try await diarizer.loadModels()
            try Task.checkCancellation()
            let diarizationResult = try await diarizeWithWatchdog(
                diarizer: diarizer,
                samples: samples,
                sampleRate: sampleRate
            )
            try Task.checkCancellation()
            let normalizedSegments = normalizedDiarizationSegments(
                diarizationResult.segments,
                audioDuration: diarizationResult.audioDuration
            )

            guard !normalizedSegments.isEmpty else {
                Log.transcription.warning("Speaker diarization returned no usable segments. Falling back to plain transcript.")
                return try await transcribeWithoutDiarization(engine: engine, audioData: audioData, options: options)
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

            Log.transcription.warning("Speaker diarization produced no transcript text. Falling back to plain transcript.")
            return try await transcribeWithoutDiarization(engine: engine, audioData: audioData, options: options)
        } catch is CancellationError {
            Log.transcription.info("Speaker diarization canceled")
            throw CancellationError()
        } catch {
            Log.transcription.warning("Speaker diarization unavailable, falling back to plain transcript: \(error.localizedDescription)")
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
        sampleRate: Int
    ) async throws -> DiarizationResult {
        guard let timeoutSeconds = diarizationTimeoutSeconds else {
            return try await diarizer.diarize(samples: samples, sampleRate: sampleRate)
        }

        return try await withAsyncWatchdog(
            timeoutSeconds: timeoutSeconds,
            timeoutError: { DiarizationTimeoutError(timeoutSeconds: timeoutSeconds) }
        ) {
            try await diarizer.diarize(samples: samples, sampleRate: sampleRate)
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
        segments: [SpeakerSegment],
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        let speakerLabelsByID = try speakerLabelsByID(from: segments)
        let shouldShowSpeakerLabels = speakerLabelsByID.count > 1
        let segmentOptions = await transcriptionOptionsForDiarizedSegments(
            engine: engine,
            samples: samples,
            sampleRate: sampleRate,
            options: options
        )
        var transcriptSegments: [DiarizedTranscriptSegment] = []
        var textLines: [String] = []

        for segment in segments {
            try Task.checkCancellation()
            guard let segmentData = extractAudioData(
                samples: samples,
                sampleRate: sampleRate,
                startTime: segment.startTime,
                endTime: segment.endTime
            ) else {
                continue
            }

            let segmentText = try await engine.transcribe(audioData: segmentData, options: segmentOptions)
            let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let speakerID = segment.speaker.id
            let resolvedSpeakerLabel = speakerLabelsByID[speakerID] ?? "Speaker 1"
            let visibleSpeakerLabel = shouldShowSpeakerLabels ? resolvedSpeakerLabel : ""

            let diarizedSegment = DiarizedTranscriptSegment(
                speakerId: speakerID,
                speakerLabel: visibleSpeakerLabel,
                speakerEmbedding: segment.speaker.embedding,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                text: trimmed
            )

            let splitSegments = splitTranscriptSegmentIfNeeded(diarizedSegment)
            transcriptSegments.append(contentsOf: splitSegments)
            if shouldShowSpeakerLabels {
                textLines.append(contentsOf: splitSegments.map { "\(resolvedSpeakerLabel): \($0.text)" })
            }
        }

        let mergedText: String
        if !shouldShowSpeakerLabels {
            if !transcriptSegments.isEmpty {
                Log.transcription.info("Speaker diarization detected a single speaker; omitting labels from transcript output")
            }
            mergedText = transcriptSegments
                .map(\.text)
                .joined(separator: " ")
        } else {
            mergedText = textLines.joined(separator: "\n")
        }

        return TranscriptionOutput(
            text: mergedText,
            diarizedSegments: transcriptSegments.isEmpty ? nil : transcriptSegments
        )
    }

    private func transcriptionOptionsForDiarizedSegments(
        engine: any TranscriptionEngine,
        samples: [Float],
        sampleRate: Int,
        options: TranscriptionOptions
    ) async -> TranscriptionOptions {
        guard options.language == .automatic else {
            return options
        }

        do {
            guard let detectedLanguage = try await engine.detectLanguage(samples: samples, sampleRate: sampleRate),
                  detectedLanguage != .automatic else {
                return options
            }

            Log.transcription.info("Pinned detected language for diarized transcription segments: \(detectedLanguage.rawValue)")
            return TranscriptionOptions(
                language: detectedLanguage,
                vocabularyBiasWords: options.vocabularyBiasWords
            )
        } catch {
            Log.transcription.warning(
                "Language detection for diarized transcription failed; using per-segment automatic detection: \(error.localizedDescription)"
            )
            return options
        }
    }

    private func speakerLabelsByID(from segments: [SpeakerSegment]) throws -> [String: String] {
        let knownSpeakerIDs = Set((try speakerIdentityService?.knownSpeakers() ?? []).map(\.id))
        let matchedLabelsByID = try matchedSpeakerLabelsByID(from: segments)
        var labelsByID: [String: String] = [:]
        var fallbackSpeakerIndex = 1

        for segment in segments {
            try Task.checkCancellation()
            let speakerID = segment.speaker.id
            guard labelsByID[speakerID] == nil else { continue }

            if let matchedLabel = matchedLabelsByID[speakerID] {
                labelsByID[speakerID] = matchedLabel
                continue
            }

            let providedLabel = segment.speaker.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !providedLabel.isEmpty && !knownSpeakerIDs.contains(speakerID) {
                labelsByID[speakerID] = providedLabel
            } else {
                labelsByID[speakerID] = "Speaker \(fallbackSpeakerIndex)"
                fallbackSpeakerIndex += 1
            }
        }

        return labelsByID
    }

    private func matchedSpeakerLabelsByID(from segments: [SpeakerSegment]) throws -> [String: String] {
        guard let speakerIdentityService else { return [:] }

        var segmentsBySpeakerID: [String: [SpeakerSegment]] = [:]
        for segment in segments {
            try Task.checkCancellation()
            segmentsBySpeakerID[segment.speaker.id, default: []].append(segment)
        }

        var labelsByID: [String: String] = [:]
        for (speakerID, speakerSegments) in segmentsBySpeakerID {
            try Task.checkCancellation()
            guard let representativeEmbedding = representativeEmbedding(from: speakerSegments),
                  let match = try speakerIdentityService.bestMatch(for: representativeEmbedding) else {
                continue
            }

            labelsByID[speakerID] = match.displayName
        }

        return labelsByID
    }

    private func representativeEmbedding(from segments: [SpeakerSegment]) -> [Float]? {
        segments
            .sorted { lhs, rhs in
                if lhs.duration == rhs.duration {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.duration > rhs.duration
            }
            .compactMap(\.speaker.embedding)
            .first(where: { !$0.isEmpty })
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
        _ segments: [SpeakerSegment],
        audioDuration: TimeInterval
    ) -> [SpeakerSegment] {
        let clampedSegments: [SpeakerSegment] = segments
            .compactMap { segment in
                let start = max(0, min(segment.startTime, audioDuration))
                let end = max(0, min(segment.endTime, audioDuration))
                guard end > start else { return nil }
                return SpeakerSegment(
                    speaker: segment.speaker,
                    startTime: start,
                    endTime: end,
                    confidence: segment.confidence
                )
            }
            .sorted { $0.startTime < $1.startTime }

        guard !clampedSegments.isEmpty else { return [] }

        var mergedSegments: [SpeakerSegment] = []
        mergedSegments.reserveCapacity(clampedSegments.count)

        for segment in clampedSegments {
            guard let previous = mergedSegments.last else {
                mergedSegments.append(segment)
                continue
            }

            let gap = segment.startTime - previous.endTime
            let sameSpeaker = previous.speaker.id == segment.speaker.id

            if sameSpeaker && gap <= Self.diarizationMergeGapSeconds {
                let previousDuration = max(previous.duration, 0.001)
                let currentDuration = max(segment.duration, 0.001)
                let combinedDuration = previousDuration + currentDuration
                let weightedConfidence = (
                    previous.confidence * Float(previousDuration) +
                    segment.confidence * Float(currentDuration)
                ) / Float(combinedDuration)

                let mergedSpeaker = Speaker(
                    id: previous.speaker.id,
                    label: previous.speaker.label,
                    embedding: previous.speaker.embedding ?? segment.speaker.embedding
                )

                let merged = SpeakerSegment(
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

    private func extractAudioData(
        samples: [Float],
        sampleRate: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Data? {
        guard sampleRate > 0, !samples.isEmpty else { return nil }

        let startIndex = max(0, min(samples.count - 1, Int((startTime * Double(sampleRate)).rounded(.down))))
        let endIndex = max(startIndex, min(samples.count, Int((endTime * Double(sampleRate)).rounded(.up))))
        guard endIndex > startIndex else { return nil }

        let minimumSamples = Int(Double(sampleRate) * Self.minimumSegmentDurationSeconds)
        guard (endIndex - startIndex) >= minimumSamples else { return nil }

        let segmentSamples = Array(samples[startIndex..<endIndex])
        return segmentSamples.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }
    }

    private func prepareSpeakerDiarizer() async throws -> any SpeakerDiarizer {
        let diarizer = getOrCreateSpeakerDiarizer()
        await diarizer.clearKnownSpeakers()

        guard let speakerIdentityService else {
            return diarizer
        }

        for speaker in try speakerIdentityService.knownSpeakers() {
            try Task.checkCancellation()
            try await diarizer.registerKnownSpeaker(speaker)
        }

        return diarizer
    }

    private func getOrCreateSpeakerDiarizer() -> any SpeakerDiarizer {
        if let speakerDiarizer {
            return speakerDiarizer
        }

        let created = speakerDiarizerFactory()
        speakerDiarizer = created
        return created
    }

    private static func defaultEngineFactory(
        provider: ModelManager.ModelProvider
    ) throws -> any TranscriptionEngine {
        switch provider {
        case .whisperKit:
            return WhisperKitEngine()
        case .parakeet:
            return ParakeetEngine()
        case .appleSpeech:
            return AppleSpeechEngine()
        default:
            throw TranscriptionError.modelLoadFailed("Provider \(provider.rawValue) not supported locally")
        }
    }

    private func getDownloadBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Pindrop", isDirectory: true)
    }

    private nonisolated static func modelLoadTimeoutError(after timeoutSeconds: TimeInterval) -> TranscriptionError {
        .modelLoadFailed(
            "Model loading timed out after \(Int(timeoutSeconds))s. This can happen on first launch after an update. Try restarting the app, or delete and re-download the model from Settings."
        )
    }

    private func getStreamingModelBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private func applyStreamingCallbacks() {
        guard let streamingEngine else { return }

        // Engine setters are actor-isolated; hop from this sync context. Session
        // start always awaits prepare/start after this, so the setters land before
        // the first buffer is processed.
        Task {
            await streamingEngine.setTranscriptionCallback { [weak self] result in
                guard !result.isFinal else { return }
                Task { @MainActor [weak self] in
                    self?.streamingPartialCallback?(result.text)
                }
            }

            await streamingEngine.setEndOfUtteranceCallback { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.streamingFinalUtteranceCallback?(text)
                }
            }
        }
    }

    private func dataToFloatArray(_ data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)

        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for index in 0..<floatCount {
                floatArray[index] = floatBuffer[index]
            }
        }

        return floatArray
    }
}

private struct DiarizationTimeoutError: Error, LocalizedError {
    let timeoutSeconds: TimeInterval

    var errorDescription: String? {
        "Speaker diarization timed out after \(Int(timeoutSeconds)) seconds."
    }
}

private final class AsyncWatchdogState<Output>: @unchecked Sendable {
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

@MainActor
private func withAsyncWatchdog<Output>(
    timeoutSeconds: TimeInterval,
    timeoutError: @escaping @Sendable () -> Error,
    operation: @escaping @MainActor () async throws -> Output
) async throws -> Output {
    let state = AsyncWatchdogState<Output>()

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
