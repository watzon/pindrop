//
//  StreamingSessionControllerTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import Foundation
import AVFoundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
@Suite
struct StreamingSessionControllerTests {
    private struct OutputFailure: Error {}

    private final class RecordingClipboard: ClipboardProtocol, @unchecked Sendable {
        private(set) var copied: [String] = []

        func copyToClipboard(_ text: String) -> Bool {
            copied.append(text)
            return true
        }

        func captureSnapshot() -> ClipboardSnapshot { .empty }
        func currentChangeCount() -> Int { copied.count }
        func currentStringContent() -> String? { copied.last }
        func restoreSnapshot(_ snapshot: ClipboardSnapshot) -> Bool { true }
    }

    private final class RecordingToastPresenter: ToastPresenting, @unchecked Sendable {
        private(set) var payloads: [ToastPayload] = []

        func show(
            payload: ToastPayload,
            onAction: @escaping (UUID) -> Void,
            onHoverChange: @escaping (Bool) -> Void
        ) {
            payloads.append(payload)
        }

        func hide() {}
    }

    private func makeDictionaryStore() throws -> DictionaryStore {
        let schema = Schema([VocabularyWord.self, WordReplacement.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return DictionaryStore(modelContext: ModelContext(container))
    }

    private func makeController(
        clipboard: RecordingClipboard,
        toastPresenter: RecordingToastPresenter,
        transcriptionService: TranscriptionService? = nil
    ) throws -> StreamingSessionController {
        let settings = SettingsStore()
        settings.resetAllSettings()
        settings.addTrailingSpace = false
        settings.streamingPostStopEnhancementEnabled = false

        let outputManager = OutputManager(
            outputMode: .clipboard,
            clipboard: clipboard,
            accessibilityPermissionChecker: { false }
        )
        let toastService = ToastService(presenter: toastPresenter)
        let permissionManager = PermissionManager()
        let audioRecorder = try AudioRecorder(permissionManager: permissionManager)

        return StreamingSessionController(
            transcriptionService: transcriptionService ?? TranscriptionService(),
            settingsStore: settings,
            dictionaryStore: try makeDictionaryStore(),
            outputManager: outputManager,
            toastService: toastService,
            liveTranscriptState: LiveTranscriptState(),
            audioRecorder: audioRecorder,
            normalizeText: { AppCoordinator.normalizedTranscriptionText($0) },
            isEffectivelyEmptyText: { AppCoordinator.isTranscriptionEffectivelyEmpty($0) }
        )
    }


    @Test func cancelledFinalizeInsertionDoesNotClipboardOrToast() async throws {
        let clipboard = RecordingClipboard()
        let toastPresenter = RecordingToastPresenter()
        let controller = try makeController(clipboard: clipboard, toastPresenter: toastPresenter)

        actor Gate {
            private var isOpen = false
            private var waiters: [CheckedContinuation<Void, Never>] = []

            func open() {
                isOpen = true
                let pending = waiters
                waiters.removeAll()
                for waiter in pending { waiter.resume() }
            }

            func waitUntilOpen() async {
                if isOpen { return }
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            }
        }

        let gate = Gate()
        let task = Task { @MainActor in
            await gate.waitUntilOpen()
            return try await controller.finalizeInsertionForTesting(finalText: "hello cancelled")
        }

        // Cancel before the insertion stage runs so cooperative cancellation is observed
        // before any paste/clipboard fallback.
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        #expect(clipboard.copied.isEmpty)
        #expect(toastPresenter.payloads.isEmpty)
    }

    @Test func outputErrorRacingCancellationDoesNotClipboardOrToast() async throws {
        let clipboard = RecordingClipboard()
        let toastPresenter = RecordingToastPresenter()
        let controller = try makeController(clipboard: clipboard, toastPresenter: toastPresenter)

        actor Gate {
            private var isOpen = false
            private var waiters: [CheckedContinuation<Void, Never>] = []

            func open() {
                isOpen = true
                let pending = waiters
                waiters.removeAll()
                for waiter in pending { waiter.resume() }
            }

            func waitUntilOpen() async {
                if isOpen { return }
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            }
        }

        let gate = Gate()
        // Production path: custom output failure can race with cancellation. The shared
        // performFinalStreamingInsertion catch must prefer task cancellation over
        // clipboard/toast fallback.
        controller.setFinalInsertionOverrideForTesting { _ in
            await gate.waitUntilOpen()
            throw OutputFailure()
        }

        let task = Task { @MainActor in
            try await controller.finalizeInsertionForTesting(finalText: "race me")
        }

        // Cancel while insertion is in-flight, then release the failing output.
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        #expect(clipboard.copied.isEmpty)
        #expect(toastPresenter.payloads.isEmpty)
    }

    @Test func cancellationAfterSuccessfulInsertionKeepsOutcome() async throws {
        let clipboard = RecordingClipboard()
        let toastPresenter = RecordingToastPresenter()
        let controller = try makeController(clipboard: clipboard, toastPresenter: toastPresenter)

        // The override "lands" the paste and then the operation is cancelled before
        // the controller returns. The committed output must still reach the caller
        // (so history is persisted) instead of collapsing into CancellationError.
        controller.setFinalInsertionOverrideForTesting { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .pasted(destinationAppName: "TextEdit", destinationAppBundleID: "com.apple.TextEdit")
        }

        let task = Task { @MainActor in
            try await controller.finalizeInsertionForTesting(finalText: "committed text")
        }
        let outcome = try await task.value

        #expect(outcome.outputSucceeded)
        #expect(outcome.didPaste)
        #expect(outcome.destinationAppName == "TextEdit")
        #expect(clipboard.copied.isEmpty)
        #expect(toastPresenter.payloads.isEmpty)
    }

    @Test func cancellationPolicyRejectsOnlyCancellationErrors() {
        #expect(StreamingSessionController.isCancellationError(CancellationError()))
        #expect(StreamingSessionController.isCancellationError(URLError(.cancelled)))
        #expect(StreamingSessionController.isCancellationError(OutputManagerError.clipboardWriteFailed) == false)
    }

    @Test func beginInstallsCallbacksAndStartsStreamingEngineOnce() async throws {
        let clipboard = RecordingClipboard()
        let toastPresenter = RecordingToastPresenter()

        final class CountingStreamingEngine: StreamingTranscriptionEngine, @unchecked Sendable {
            private(set) var state: StreamingTranscriptionState = .unloaded
            private(set) var loadCallCount = 0
            private(set) var startStreamingCallCount = 0
            private(set) var transcriptionCallbackInstallCount = 0
            private(set) var endOfUtteranceCallbackInstallCount = 0
            /// Captured synchronously inside `loadModel` / `startStreaming` so the
            /// assertions are ordering-based, not scheduling-sensitive.
            private(set) var hadBothCallbacksInstalledAtLoad = false
            private(set) var hadBothCallbacksInstalledAtStart = false

            func loadModel(name: String) async throws {
                hadBothCallbacksInstalledAtLoad =
                    transcriptionCallbackInstallCount > 0
                    && endOfUtteranceCallbackInstallCount > 0
                loadCallCount += 1
                state = .ready
            }

            func unloadModel() async {
                state = .unloaded
            }

            func startStreaming() async throws {
                hadBothCallbacksInstalledAtStart =
                    transcriptionCallbackInstallCount > 0
                    && endOfUtteranceCallbackInstallCount > 0
                startStreamingCallCount += 1
                state = .streaming
            }

            func stopStreaming() async throws -> String {
                state = .ready
                return ""
            }

            func pauseStreaming() async {
                state = .paused
            }

            func resumeStreaming() async throws {
                state = .streaming
            }

            func processAudioChunk(_ samples: [Float]) async throws {}
            func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {}

            func setTranscriptionCallback(_ callback: @escaping StreamingTranscriptionCallback) async {
                transcriptionCallbackInstallCount += 1
            }

            func setEndOfUtteranceCallback(_ callback: @escaping EndOfUtteranceCallback) async {
                endOfUtteranceCallbackInstallCount += 1
            }

            func reset() async {
                state = .ready
            }
        }

        let engine = CountingStreamingEngine()
        var factoryCallCount = 0
        var profileProviderCallCount = 0
        var backendProviderCallCount = 0
        let transcriptionService = TranscriptionService(
            streamingEngineFactory: { _ in
                factoryCallCount += 1
                return engine
            },
            streamingChunkProfileProvider: {
                profileProviderCallCount += 1
                return .standard
            },
            streamingBackendProvider: {
                backendProviderCallCount += 1
                return .parakeet
            }
        )

        let controller = try makeController(
            clipboard: clipboard,
            toastPresenter: toastPresenter,
            transcriptionService: transcriptionService
        )

        await controller.begin()

        #expect(controller.isSessionActive)
        // Both engine callbacks must already be installed when load and start run.
        #expect(engine.hadBothCallbacksInstalledAtLoad)
        #expect(engine.hadBothCallbacksInstalledAtStart)
        #expect(engine.transcriptionCallbackInstallCount == 1)
        #expect(engine.endOfUtteranceCallbackInstallCount == 1)
        #expect(engine.loadCallCount == 1)
        #expect(engine.startStreamingCallCount == 1)
        #expect(factoryCallCount == 1)
        // One prepare evaluation only (no explicit prepare + startStreaming prepare).
        #expect(profileProviderCallCount == 1)
        #expect(backendProviderCallCount == 1)
        #expect(engine.state == .streaming)
        #expect(transcriptionService.state == .transcribing)

        await controller.cancel()
    }

}
