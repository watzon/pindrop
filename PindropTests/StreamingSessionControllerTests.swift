//
//  StreamingSessionControllerTests.swift
//  PindropTests
//
//  Created on 2026-07-13.
//

import Foundation
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
        toastPresenter: RecordingToastPresenter
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
            transcriptionService: TranscriptionService(),
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

    @Test func cancellationPolicyRejectsOnlyCancellationErrors() {
        #expect(StreamingSessionController.isCancellationError(CancellationError()))
        #expect(StreamingSessionController.isCancellationError(URLError(.cancelled)))
        #expect(StreamingSessionController.isCancellationError(OutputManagerError.clipboardWriteFailed) == false)
    }
}
