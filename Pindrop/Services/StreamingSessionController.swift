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
    private var audioProcessingTask: Task<Void, Never>?
    private var refinementCoordinator: StreamingRefinementCoordinator?
    /// Strongly retained here — `StreamingRefinementCoordinator` holds its sink weakly.
    private var overlaySink: OverlayStreamingSink?

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
            try await transcriptionService.prepareStreamingEngine()
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
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)

        let finalStreamedText: String
        do {
            finalStreamedText = try await transcriptionService.stopStreaming()
            Log.transcription.info("Streaming transcription finalized")
        } catch {
            Log.transcription.error("Failed to stop streaming transcription: \(error)")
            await cancel()
            throw error
        }

        clearBindings(cancelPendingWork: false)
        isSessionActive = false

        var (textAfterReplacements, appliedReplacements) =
            try dictionaryStore.applyReplacements(to: finalStreamedText)
        textAfterReplacements = normalizeText(textAfterReplacements)
        if !appliedReplacements.isEmpty {
            Log.app.info("Applied \(appliedReplacements.count) dictionary replacements")
        }

        // If the refinement coordinator is active, it owns the authoritative final text:
        // fold dictionary replacements onto its refined output rather than the raw stream.
        // The coordinator's drained text is the currently-displayed string; dictionary
        // replacements run on top, and the sink's finishStreamingInsertion below lands
        // the post-replacement text in the target app with a single paste.
        let coord = refinementCoordinator
        if let coord {
            let coordText = await coord.awaitFinalTextAndDrain()
            let (coordAfterReplacements, coordReplacements) = try dictionaryStore.applyReplacements(
                to: coordText
            )
            textAfterReplacements = normalizeText(coordAfterReplacements)
            appliedReplacements = coordReplacements
            if !coordReplacements.isEmpty {
                Log.app.info(
                    "Applied \(coordReplacements.count) dictionary replacements to refined stream")
            }
        }

        guard !isEffectivelyEmptyText(textAfterReplacements) else {
            // Empty finish collapses the overlay without pasting anything.
            try? await overlaySink?.finishStreamingInsertion(
                finalText: "", appendTrailingSpace: false)
            refinementCoordinator = nil
            return FinalizeOutcome(
                finalText: "",
                originalStreamedText: nil,
                enhancedWithModel: nil,
                appliedReplacements: appliedReplacements,
                outputSucceeded: false
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
            liveTranscriptState.beginEnhancing()
            do {
                let language = settingsStore.selectedAppLanguage
                let timeout = Self.offlineRetranscriptionTimeout(recordingDuration: recordingDuration)
                let refinedText = try await Self.withFinalizeTimeout(
                    nanoseconds: UInt64(timeout * 1_000_000_000)
                ) { [transcriptionService] in
                    try await transcriptionService.transcribe(
                        audioData: recordedAudioData,
                        diarizationEnabled: false,
                        options: TranscriptionOptions(language: language)
                    ).text
                }
                let (refinedAfterReplacements, refinedReplacements) =
                    try dictionaryStore.applyReplacements(to: refinedText)
                let normalizedRefined = normalizeText(refinedAfterReplacements)
                if !isEffectivelyEmptyText(normalizedRefined) {
                    textAfterReplacements = normalizedRefined
                    appliedReplacements = refinedReplacements
                    Log.transcription.info(
                        "Streaming finalize: offline re-transcription applied (\(normalizedRefined.count) chars)"
                    )
                } else {
                    Log.transcription.info(
                        "Streaming finalize: offline re-transcription was empty; keeping streamed text"
                    )
                }
            } catch {
                Log.transcription.warning(
                    "Streaming finalize: offline re-transcription failed, keeping streamed text: \(error.localizedDescription)"
                )
            }
        }

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
            } catch {
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

        var outputSucceeded = false
        do {
            // Single atomic insertion into the target app; the sink collapses the
            // overlay whether or not the paste succeeds.
            try await ensureOverlaySink().finishStreamingInsertion(
                finalText: textAfterReplacements,
                appendTrailingSpace: settingsStore.addTrailingSpace
            )
            outputSucceeded = true
            Log.transcription.debug("Applied final streaming transcription output")
        } catch {
            Log.output.error("Final streaming insertion failed: \(error)")
            // The paste never landed — put the transcript on the clipboard so the
            // session's text is recoverable, and tell the user what happened.
            if (try? outputManager.copyToClipboard(textAfterReplacements)) != nil {
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
        }

        coord?.endSession()
        refinementCoordinator = nil

        return FinalizeOutcome(
            finalText: textAfterReplacements,
            originalStreamedText: originalStreamedText,
            enhancedWithModel: enhancedWithModel,
            appliedReplacements: appliedReplacements,
            outputSucceeded: outputSucceeded
        )
    }

    // MARK: - Private — engine plumbing

    private func setEngineCallbacks() {
        transcriptionService.setStreamingCallbacks(
            onPartial: { [weak self] text in
                Task { @MainActor in
                    await self?.refinementCoordinator?.ingestPartial(text)
                }
            },
            onFinalUtterance: { [weak self] text in
                Task { @MainActor in
                    await self?.refinementCoordinator?.ingestFinal(text)
                }
            }
        )
    }

    private func attachAudioForwarding() {
        audioRecorder.onAudioBuffer = { [weak self] buffer in
            self?.enqueueAudioBuffer(buffer)
        }
    }

    private func enqueueAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isSessionActive else { return }

        let previousTask = audioProcessingTask
        audioProcessingTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self, self.isSessionActive else { return }
            do {
                try await self.transcriptionService.processStreamingAudioBuffer(buffer)
            } catch {
                Log.transcription.error("Streaming audio buffer processing failed: \(error)")
            }
        }
    }

    private func flushPendingAudioWork() async {
        if let task = audioProcessingTask {
            _ = await task.result
        }
        audioProcessingTask = nil
    }

    private func clearBindings(cancelPendingWork: Bool) {
        audioRecorder.onAudioBuffer = nil
        transcriptionService.setStreamingCallbacks(onPartial: nil, onFinalUtterance: nil)
        if cancelPendingWork {
            audioProcessingTask?.cancel()
            audioProcessingTask = nil
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

    // MARK: - Private — timeout

    /// Bounds a finalize-path step: whichever of `operation` or the deadline finishes
    /// first wins, and the loser is cancelled. Callers catch the timeout and fall back
    /// to the text they already have — the paste must never wait indefinitely.
    private nonisolated static func withFinalizeTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw FinalizeStepTimedOut()
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw FinalizeStepTimedOut()
            }
            return value
        }
    }
}
