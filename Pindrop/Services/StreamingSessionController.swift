//
//  StreamingSessionController.swift
//  Pindrop
//
//  Created on 2026-07-06.
//
//  Owns the live-transcription session lifecycle that previously sprawled through
//  AppCoordinator: engine callbacks, the serialized audio-buffer forwarding queue,
//  the StreamingRefinementCoordinator + overlay-sink pair, and the post-stop
//  finalize pipeline (drain → dictionary replacements → offline re-transcription →
//  optional LLM enhancement → single atomic paste, each stage bounded by a
//  timeout). AppCoordinator keeps what is genuinely app-level: the availability
//  gate for the session, recording UI transitions, no-speech messaging, and
//  history persistence.
//

import Foundation
import AVFoundation

@MainActor
final class StreamingSessionController {

    // MARK: - Outcome

    /// What the finalize pipeline produced, for the coordinator to persist/report.
    struct FinalizeOutcome {
        /// Final text after replacements/refinement/enhancement. Empty when the
        /// session produced no effective speech (the overlay was collapsed without
        /// pasting; the coordinator surfaces the no-speech message).
        let finalText: String
        /// The pre-enhancement text when the LLM pass rewrote it, nil otherwise.
        let originalStreamedText: String?
        /// Model ID of the post-stop enhancement when applied.
        let enhancedWithModel: String?
        /// Dictionary replacements applied to the text that was pasted.
        let appliedReplacements: [(original: String, replacement: String)]
        let outputSucceeded: Bool
        /// Frontmost app at insert/copy time (from OutputManager).
        let destinationAppName: String?
        let destinationAppBundleID: String?
        /// True when the paste keystroke landed (not clipboard-only fallback).
        let didPaste: Bool

        var isEffectivelyEmpty: Bool { finalText.isEmpty }
    }

    // MARK: - Timeouts

    /// Bounds for the offline finalize re-transcription. The bound scales with the
    /// recording length — batch decode is usually much faster than realtime, but on
    /// slow hardware a long dictation can legitimately approach realtime, and a
    /// flat cap would discard a *succeeding* high-quality pass. The floor keeps
    /// short sessions snappy; the ceiling keeps a wedged engine from pinning the
    /// overlay in "Enhancing…" forever.
    static let offlineRetranscriptionTimeoutFloor: TimeInterval = 30
    static let offlineRetranscriptionTimeoutCeiling: TimeInterval = 120

    static func offlineRetranscriptionTimeout(recordingDuration: TimeInterval) -> TimeInterval {
        min(offlineRetranscriptionTimeoutCeiling,
            max(offlineRetranscriptionTimeoutFloor, recordingDuration * 1.5))
    }

    /// Upper bound on the post-stop LLM enhancement call (network + inference).
    static let postStopEnhanceTimeoutNanoseconds: UInt64 = 20_000_000_000
    /// Keep the live path close to real time under a slow decoder. On overflow,
    /// discard the oldest pending buffers and retain the newest 32 (~8 seconds at
    /// a 4,096-frame 16 kHz tap), while the file-backed recorder still retains the
    /// complete waveform for offline finalization.
    nonisolated static let maximumBufferedAudioBuffers = 32

    private struct FinalizeStepTimedOut: Error {}

    // MARK: - Dependencies

    private let transcriptionService: TranscriptionService
    private let settingsStore: SettingsStore
    private let dictionaryStore: DictionaryStore
    private let outputManager: OutputManager
    private let toastService: ToastService
    private let liveTranscriptState: LiveTranscriptState
    private let audioRecorder: AudioRecorder
    private let normalizeText: (String) -> String
    private let isEffectivelyEmptyText: (String) -> Bool

    /// The coordinator's post-stop LLM pass (it needs prompt presets and the
    /// enhancement service, which stay app-level). Wired via `configure` after
    /// AppCoordinator finishes initializing; nil means "no enhancement".
    private var postStopEnhance: (@MainActor (String) async -> (enhancedText: String, modelID: String)?)?

    // MARK: - Session state

    private(set) var isSessionActive = false
    /// Direct engine handle for the audio pump. Captured once per session so the
    /// per-buffer path never hops through the @MainActor TranscriptionService.
    private var pumpEngine: (any StreamingTranscriptionEngine)?
    private var audioStreamContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var audioConsumerTask: Task<Void, Never>?
    private var refinementCoordinator: StreamingRefinementCoordinator?
    /// Strongly retained here — `StreamingRefinementCoordinator` holds its sink weakly.
    private var overlaySink: OverlayStreamingSink?
    /// Test-only override for the final paste step so races with cancellation can be exercised
    /// without depending on Accessibility/KeySimulation hardware paths.
    private var finalInsertionOverrideForTesting: ((String) async throws -> OutputManager.OutputResult)?

    init(
        transcriptionService: TranscriptionService,
        settingsStore: SettingsStore,
        dictionaryStore: DictionaryStore,
        outputManager: OutputManager,
        toastService: ToastService,
        liveTranscriptState: LiveTranscriptState,
        audioRecorder: AudioRecorder,
        normalizeText: @escaping (String) -> String,
        isEffectivelyEmptyText: @escaping (String) -> Bool
    ) {
        self.transcriptionService = transcriptionService
        self.settingsStore = settingsStore
        self.dictionaryStore = dictionaryStore
        self.outputManager = outputManager
        self.toastService = toastService
        self.liveTranscriptState = liveTranscriptState
        self.audioRecorder = audioRecorder
        self.normalizeText = normalizeText
        self.isEffectivelyEmptyText = isEffectivelyEmptyText
    }

    func configure(
        postStopEnhance: @escaping @MainActor (String) async -> (enhancedText: String, modelID: String)?
    ) {
        self.postStopEnhance = postStopEnhance
    }

    // MARK: - Lifecycle

    /// Stands up a streaming session: engine callbacks, engine start, refinement
    /// coordinator + overlay sink, and audio forwarding. On failure the session is
    /// cancelled internally and `isSessionActive` stays false — the caller falls
    /// back to batch transcription.
    func begin() async {
        do {
            setEngineCallbacks()
            // startStreaming prepares the engine once; avoid a redundant prepare round-trip.
            try await transcriptionService.startStreaming()

            // Surface a one-time toast if the Apple backend was requested but we had to
            // fall back to Parakeet (e.g. running on macOS < 26 or unsupported locale).
            if transcriptionService.consumeAppleBackendFallbackFlag() {
                toastService.show(
                    ToastPayload(
                        message: localized(
                            "Apple SpeechTranscriber unavailable — using Nemotron",
                            locale: .autoupdatingCurrent
                        ),
                        style: .standard
                    )
                )
            }

            // The coordinator always stands up. It owns the committed/tentative split,
            // LocalAgreement-2 commit rules, and deterministic cleanup — none of which
            // need an LLM. Its sink is the overlay: live text renders in the floating
            // indicator, and the target app receives one paste at session finish.
            let coord = StreamingRefinementCoordinator()
            coord.beginSession(outputSink: ensureOverlaySink())
            refinementCoordinator = coord
            if let refinementAssignment = settingsStore.resolveAssignment(for: .streamingRefinement) {
                Log.transcription.info(
                    "Streaming refinement coordinator engaged (provider=\(refinementAssignment.kind.rawValue), model=\(refinementAssignment.modelID)) — live LLM refinement disabled in Phase 2, post-stop path unchanged"
                )
            } else {
                Log.transcription.info(
                    "Streaming refinement coordinator engaged with deterministic cleanup only"
                )
            }

            pumpEngine = transcriptionService.activeStreamingEngine
            attachAudioForwarding()
            isSessionActive = true
            Log.transcription.info("Streaming transcription enabled for current session")
        } catch {
            Log.transcription.error("Streaming transcription unavailable, falling back to batch: \(error)")
            await cancel()
        }
    }

    /// Marks streaming unused for this session and clears any stale bindings.
    func deactivate() {
        isSessionActive = false
        clearBindings(cancelPendingWork: true)
    }

    /// Abort the streaming session: tear down callbacks, cancel the engine, and
    /// collapse the overlay. Nothing was inserted into the target app, so there is
    /// no text to preserve or remove.
    func cancel() async {
        clearBindings(cancelPendingWork: true)
        await transcriptionService.cancelStreaming()
        if let coord = refinementCoordinator {
            await coord.cancelSession()
            refinementCoordinator = nil
        } else {
            await overlaySink?.cancelStreamingInsertion()
        }
        isSessionActive = false
    }

    /// Synchronous abort for cancellation paths that cannot await (double-escape):
    /// bindings drop and the session flag clears immediately; the engine/overlay
    /// teardown runs in a detached task so the session doesn't dangle.
    func cancelDetached() {
        let hadSession = isSessionActive
        clearBindings(cancelPendingWork: true)
        isSessionActive = false
        guard hadSession else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.transcriptionService.cancelStreaming()
            // Collapse the overlay via the coordinator (which cancels the sink); also
            // nil it out so the session doesn't dangle past the cancellation.
            if let coord = self.refinementCoordinator {
                await coord.cancelSession()
                self.refinementCoordinator = nil
            } else {
                await self.overlaySink?.cancelStreamingInsertion()
            }
        }
    }

    // MARK: - Finalize

    /// Drains and stops the engine, then runs the finalize pipeline: dictionary
    /// replacements → offline re-transcription (timeout-bounded, scaled to the
    /// recording length) → optional post-stop LLM enhancement (timeout-bounded) →
    /// single atomic paste via the overlay sink.
    /// Throws when the engine fails to stop (after cancelling the session).
    func finalize(recordedAudioData: Data, recordingDuration: TimeInterval) async throws -> FinalizeOutcome {
        await flushPendingAudioWork()
        try ensureNotCancelled()
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)

        let finalStreamedText: String
        do {
            finalStreamedText = try await transcriptionService.stopStreaming()
            Log.transcription.info("Streaming transcription finalized")
        } catch {
            if Self.isCancellationError(error) {
                await cancel()
                throw CancellationError()
            }
            Log.transcription.error("Failed to stop streaming transcription: \(error)")
            await cancel()
            throw error
        }

        try ensureNotCancelled()
        clearBindings(cancelPendingWork: false)
        isSessionActive = false

        // Live/refinement text first. Empty live transcripts short-circuit before the
        // offline re-transcription pass (and its Enhancing affordance), matching the
        // pre-dictionary-semantics finalize ordering.
        var candidateRawText = finalStreamedText
        let coord = refinementCoordinator
        if let coord {
            // Coordinator text is what is currently displayed; use it as the stream
            // fallback when offline re-transcription is unavailable.
            candidateRawText = await coord.awaitFinalTextAndDrain()
            try ensureNotCancelled()
        }

        // Preview apply without usage tracking so a later offline winner does not
        // double-count, and empty sessions do not pay for offline re-transcription.
        try ensureNotCancelled()
        var (textAfterReplacements, appliedReplacements) =
            try dictionaryStore.applyReplacements(to: candidateRawText, trackUsage: false)
        textAfterReplacements = normalizeText(textAfterReplacements)
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }

        guard !isEffectivelyEmptyText(textAfterReplacements) else {
            try ensureNotCancelled()
            // Empty finish collapses the overlay without pasting anything.
            try? await overlaySink?.finishStreamingInsertion(
                finalText: "", appendTrailingSpace: false)
            refinementCoordinator = nil
            return FinalizeOutcome(
                finalText: "",
                originalStreamedText: nil,
                enhancedWithModel: nil,
                appliedReplacements: appliedReplacements,
                outputSucceeded: false,
                destinationAppName: nil,
                destinationAppBundleID: nil,
                didPaste: false
            )
        }

        // Offline finalize pass: re-transcribe the recorded audio with the batch model.
        // Streaming RNNT decoding is append-only — punctuation the model doesn't emit
        // in the moment can never be inserted retroactively, so pause-dependent
        // punctuation is unreliable live. The batch model decodes the whole waveform
        // (pauses included) with full bidirectional context and places punctuation
        // correctly. The streamed text remains the live overlay preview and the
        // fallback whenever the offline pass fails, stalls, or comes back empty.
        if !recordedAudioData.isEmpty {
            try ensureNotCancelled()
            liveTranscriptState.beginEnhancing()
            do {
                let language = settingsStore.selectedAppLanguage
                let vocabularyBias = (try? dictionaryStore.vocabularyBiasWords()) ?? []
                let timeout = Self.offlineRetranscriptionTimeout(recordingDuration: recordingDuration)
                let refinedText = try await Self.withFinalizeTimeout(
                    nanoseconds: UInt64(timeout * 1_000_000_000)
                ) { [transcriptionService] in
                    try await transcriptionService.transcribe(
                        audioData: recordedAudioData,
                        diarizationEnabled: false,
                        options: TranscriptionOptions(
                            language: language,
                            vocabularyBiasWords: vocabularyBias
                        )
                    ).text
                }
                try ensureNotCancelled()
                let normalizedRefined = normalizeText(refinedText)
                if !isEffectivelyEmptyText(normalizedRefined) {
                    candidateRawText = refinedText
                    Log.transcription.info(
                        "Streaming finalize: offline re-transcription applied (\(normalizedRefined.count) chars)"
                    )
                } else {
                    Log.transcription.info(
                        "Streaming finalize: offline re-transcription was empty; keeping streamed text"
                    )
                }
            } catch is FinalizeStepTimedOut {
                // The detached batch operation may ignore cancellation. Drop its
                // engine generation before fallback so it cannot leave the shared
                // service stuck in `.transcribing` or mutate a later session.
                transcriptionService.invalidateTimedOutTranscription()
                Log.transcription.warning(
                    "Streaming finalize: offline re-transcription timed out, keeping streamed text"
                )
            } catch {
                if Self.isCancellationError(error) {
                    throw CancellationError()
                }
                Log.transcription.warning(
                    "Streaming finalize: offline re-transcription failed, keeping streamed text: \(error.localizedDescription)"
                )
            }
        }

        // Authoritative apply on the winning raw text: single usage-count batch.
        try ensureNotCancelled()
        (textAfterReplacements, appliedReplacements) =
            try dictionaryStore.applyReplacements(to: candidateRawText, trackUsage: true)
        textAfterReplacements = normalizeText(textAfterReplacements)
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }
        try ensureNotCancelled()
        try? dictionaryStore.recordVocabularyHits(in: textAfterReplacements)

        // Post-stop holistic enhancement for streaming sessions. Gated by the
        // `streamingPostStopEnhancementEnabled` setting (default OFF): the deterministic
        // cleaner is strong enough to stand on its own for most dictation, and the LLM
        // path has failure modes (preamble, conversational replies, rate-limit stalls)
        // we don't want as the default experience. Users who want LLM polish can enable
        // the toggle and configure a `transcriptionEnhancement` assignment.
        var originalStreamedText: String? = nil
        var enhancedWithModel: String? = nil
        let liveRefinementLanded = coord?.didLandAnyRefinement == true
        let enhanceEnabled = settingsStore.streamingPostStopEnhancementEnabled
        if enhanceEnabled, !liveRefinementLanded, let postStopEnhance {
            try ensureNotCancelled()
            // Surface the enhancement wait in the overlay: the transcript stays visible
            // with an "Enhancing…" affordance until the rewritten text is pasted.
            liveTranscriptState.beginEnhancing()
            let textForEnhance = textAfterReplacements
            var enhanceOutcome: (enhancedText: String, modelID: String)?
            do {
                enhanceOutcome = try await Self.withFinalizeTimeout(
                    nanoseconds: Self.postStopEnhanceTimeoutNanoseconds
                ) {
                    await postStopEnhance(textForEnhance)
                }
                try ensureNotCancelled()
            } catch {
                if Self.isCancellationError(error) {
                    throw CancellationError()
                }
                Log.aiEnhancement.warning(
                    "Streaming post-stop enhancement timed out; keeping deterministic text")
                enhanceOutcome = nil
            }
            if let result = enhanceOutcome {
                originalStreamedText = textAfterReplacements
                textAfterReplacements = result.enhancedText
                enhancedWithModel = result.modelID
                Log.transcription.info(
                    "Streaming post-stop enhancement applied: \(originalStreamedText?.count ?? 0) → \(result.enhancedText.count) chars (model=\(result.modelID))"
                )
            }
        }

        // Optional local paragraph formatting for long dictation. Runs once after any
        // enhancement and before paste/persist so history and clipboard share the result.
        textAfterReplacements = ProgrammaticTranscriptFormatter.formatIfEnabled(
            textAfterReplacements,
            enabled: settingsStore.programmaticFormattingEnabled
        )
        textAfterReplacements = normalizeText(textAfterReplacements)

        try ensureNotCancelled()
        let insertion = try await performFinalStreamingInsertion(finalText: textAfterReplacements)
        if insertion.outputSucceeded {
            Log.transcription.debug("Applied final streaming transcription output")
        }

        try ensureNotCancelled()
        coord?.endSession()
        refinementCoordinator = nil

        return FinalizeOutcome(
            finalText: textAfterReplacements,
            originalStreamedText: originalStreamedText,
            enhancedWithModel: enhancedWithModel,
            appliedReplacements: appliedReplacements,
            outputSucceeded: insertion.outputSucceeded,
            destinationAppName: insertion.outputResult?.destinationAppName,
            destinationAppBundleID: insertion.outputResult?.destinationAppBundleID,
            didPaste: insertion.outputResult?.didPaste == true
        )
    }

    /// Installs a test-only final paste implementation used by `performFinalStreamingInsertion`.
    func setFinalInsertionOverrideForTesting(
        _ override: ((String) async throws -> OutputManager.OutputResult)?
    ) {
        finalInsertionOverrideForTesting = override
    }

    /// Test seam for cancel-safe final insertion. Calls the same production path.
    func finalizeInsertionForTesting(finalText: String) async throws -> FinalizeOutcome {
        let insertion = try await performFinalStreamingInsertion(finalText: finalText)
        return FinalizeOutcome(
            finalText: finalText,
            originalStreamedText: nil,
            enhancedWithModel: nil,
            appliedReplacements: [],
            outputSucceeded: insertion.outputSucceeded,
            destinationAppName: insertion.outputResult?.destinationAppName,
            destinationAppBundleID: insertion.outputResult?.destinationAppBundleID,
            didPaste: insertion.outputResult?.didPaste == true
        )
    }

    private struct FinalStreamingInsertionResult {
        let outputSucceeded: Bool
        let outputResult: OutputManager.OutputResult?
    }

    /// Single production path for post-finalize paste/clipboard fallback.
    /// Production `finalize` and the test seam both call this exact method.
    private func performFinalStreamingInsertion(finalText: String) async throws -> FinalStreamingInsertionResult {
        try ensureNotCancelled()
        do {
            // Single atomic insertion into the target app; the sink collapses the
            // overlay whether or not the paste succeeds.
            let outputResult: OutputManager.OutputResult
            if let override = finalInsertionOverrideForTesting {
                let text = settingsStore.addTrailingSpace ? finalText + " " : finalText
                outputResult = try await override(text)
            } else {
                let sink = ensureOverlaySink()
                try await sink.finishStreamingInsertion(
                    finalText: finalText,
                    appendTrailingSpace: settingsStore.addTrailingSpace
                )
                outputResult = sink.lastOutputResult ?? .pasted()
            }
            try ensureNotCancelled()
            return FinalStreamingInsertionResult(
                outputSucceeded: true,
                outputResult: outputResult
            )
        } catch {
            // Prefer the task's current cancellation state over the thrown error so a
            // custom output failure racing cancel cannot clipboard/toast.
            try ensureNotCancelled()
            if Self.isCancellationError(error) {
                throw CancellationError()
            }
            Log.output.error("Final streaming insertion failed: \(error)")
            // The paste never landed — put the transcript on the clipboard so the
            // session's text is recoverable, and tell the user what happened.
            // Never clipboard/toast on cancellation.
            if (try? outputManager.copyToClipboard(finalText)) != nil {
                toastService.show(
                    ToastPayload(
                        message: localized(
                            "Paste failed. Transcript copied to clipboard.",
                            locale: settingsStore.selectedAppLocale.locale
                        ),
                        style: .error
                    )
                )
            }
            return FinalStreamingInsertionResult(outputSucceeded: false, outputResult: nil)
        }
    }

    // MARK: - Private — engine plumbing

    private func setEngineCallbacks() {
        // Callbacks already arrive on the main actor via TranscriptionService's
        // single isolation hop. Invoke refinement directly so finals stay ordered
        // and partials are not re-queued behind a second Task.
        transcriptionService.setStreamingCallbacks(
            onPartial: { [weak self] text in
                await self?.refinementCoordinator?.ingestPartial(text)
            },
            onFinalUtterance: { [weak self] text in
                await self?.refinementCoordinator?.ingestFinal(text)
            }
        )
    }

    /// Buffers flow: capture thread → AsyncStream → one detached consumer → engine
    /// actor. No main-actor hops anywhere in the per-buffer path: with the orb
    /// rendering at 30fps, main-actor hops throttle to ~10/sec while audio arrives
    /// at ~50/sec, so live partials stall and burst out only at stop.
    private func attachAudioForwarding() {
        guard let engine = pumpEngine else { return }

        let (stream, continuation) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .bufferingNewest(Self.maximumBufferedAudioBuffers)
        )
        audioStreamContinuation = continuation
        audioConsumerTask = Task.detached(priority: .userInitiated) {
            for await buffer in stream {
                if Task.isCancelled { break }
                do {
                    try await engine.processAudioBuffer(buffer)
                } catch {
                    Log.transcription.error("Streaming audio buffer processing failed: \(error)")
                }
            }
        }
        // The continuation is captured directly (it is Sendable); going through
        // self would re-enter the main actor from the capture thread.
        audioRecorder.onAudioBuffer = { buffer in
            if case .dropped = continuation.yield(buffer) {
                Log.transcription.warning("Streaming audio buffer backlog exceeded \(Self.maximumBufferedAudioBuffers); dropped oldest buffer")
            }
        }
    }

    private func flushPendingAudioWork() async {
        audioStreamContinuation?.finish()
        audioStreamContinuation = nil
        await audioConsumerTask?.value
        audioConsumerTask = nil
        pumpEngine = nil
    }

    private func clearBindings(cancelPendingWork: Bool) {
        audioRecorder.onAudioBuffer = nil
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)
        if cancelPendingWork {
            audioConsumerTask?.cancel()
            audioStreamContinuation?.finish()
            audioStreamContinuation = nil
            audioConsumerTask = nil
            pumpEngine = nil
        }
    }

    /// Lazily builds the long-lived overlay sink; reused across sessions.
    private func ensureOverlaySink() -> OverlayStreamingSink {
        if let overlaySink {
            return overlaySink
        }
        let sink = OverlayStreamingSink(
            transcriptState: liveTranscriptState,
            finalOutput: { [outputManager] text in
                try await outputManager.output(text)
            },
            onClipboardFallback: { [toastService] in
                toastService.show(
                    ToastPayload(
                        message: localized(
                            "Paste failed. Transcript copied to clipboard.",
                            locale: .autoupdatingCurrent
                        ),
                        style: .error
                    )
                )
            }
        )
        overlaySink = sink
        return sink
    }


    /// True when `error` is cooperative task cancellation (or URLSession cancel).
    nonisolated static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func ensureNotCancelled() throws {
        try Task.checkCancellation()
    }

    // MARK: - Private — timeout

    /// Bounds a finalize-path step: whichever of `operation` or the deadline finishes
    /// first wins, and the loser is cancelled. Callers catch the timeout and fall back
    /// to the text they already have — the paste must never wait indefinitely.
    nonisolated static func withFinalizeTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let state = FinalizeTimeoutState<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.activate(continuation) else { return }

                let operationTask = Task.detached {
                    do {
                        state.resolve(.success(try await operation()))
                    } catch {
                        state.resolve(.failure(error))
                    }
                }
                state.setOperationTask(operationTask)

                let timeoutTask = Task.detached {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    state.resolve(.failure(FinalizeStepTimedOut()))
                }
                state.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            state.resolve(.failure(CancellationError()))
        }
    }
}

/// Coordinates independently owned operation/deadline tasks so a deadline can
/// resume its caller even when the operation ignores cooperative cancellation.
/// The first result wins; late operation results are intentionally suppressed.
private final class FinalizeTimeoutState<Output>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingResult: Result<Output, Error>?
    private var isResolved = false

    func activate(_ continuation: CheckedContinuation<Output, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let pendingResult {
            self.pendingResult = nil
            continuation.resume(with: pendingResult)
            return false
        }
        guard !isResolved else {
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        return true
    }

    func setOperationTask(_ task: Task<Void, Never>) { set(task, asOperation: true) }
    func setTimeoutTask(_ task: Task<Void, Never>) { set(task, asOperation: false) }

    private func set(_ task: Task<Void, Never>, asOperation: Bool) {
        lock.lock()
        let shouldCancel = isResolved
        if !shouldCancel {
            if asOperation { operationTask = task } else { timeoutTask = task }
        }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func resolve(_ result: Result<Output, Error>) {
        lock.lock()
        guard !isResolved else { lock.unlock(); return }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        let operationTask = self.operationTask
        self.operationTask = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        if continuation == nil { pendingResult = result }
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(with: result)
    }
}
