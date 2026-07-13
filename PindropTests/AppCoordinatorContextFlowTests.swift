//
//  AppCoordinatorContextFlowTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import ApplicationServices
import Foundation
import Testing

@testable import Pindrop

@MainActor
@Suite
struct AppCoordinatorContextFlowTests {
    @Test func recordingStopRoutePreservesEveryRecordingMode() {
        let editorID = UUID()
        #expect(RecordingStopRoute.resolve(isQuickCapture: false, noteAppendEditorID: nil, isManualTranscription: false) == .dictation)
        #expect(RecordingStopRoute.resolve(isQuickCapture: true, noteAppendEditorID: nil, isManualTranscription: false) == .quickCapture)
        #expect(RecordingStopRoute.resolve(isQuickCapture: false, noteAppendEditorID: editorID, isManualTranscription: false) == .noteAppend(editorID))
        #expect(RecordingStopRoute.resolve(isQuickCapture: false, noteAppendEditorID: nil, isManualTranscription: true) == .manualTranscription)
    }

    @Test func recordingStopAdmissionLetsOnlyFirstUserOrLimitEventClaimStop() {
        let admission = RecordingStopAdmission()

        let first = admission.claim(.dictation)
        #expect(first?.route == .dictation)
        #expect(admission.claim(.quickCapture) == nil)
        if let first {
            admission.release(first)
        }
        #expect(admission.claim(.quickCapture)?.route == .quickCapture)
    }

    @Test func recordingStopAdmissionCancellationReleasesImmediatelyForNewClaim() {
        let admission = RecordingStopAdmission()
        let first = admission.claim(.dictation)
        #expect(first != nil)

        // Cancel frees the gate even while the old stop task is still alive.
        admission.invalidateCurrentClaim()
        let second = admission.claim(.quickCapture)
        #expect(second?.route == .quickCapture)

        // Stale deferred release from the cancelled stop must not clear the new claim.
        if let first {
            admission.release(first)
        }
        #expect(admission.claim(.manualTranscription) == nil)
        if let second {
            admission.release(second)
        }
        #expect(admission.claim(.manualTranscription)?.route == .manualTranscription)
    }

    @Test func recordingStopAdmissionStaleReleaseDoesNotClearNewerClaim() throws {
        let admission = RecordingStopAdmission()
        let first = try #require(admission.claim(.dictation))
        admission.release(first)

        let second = try #require(admission.claim(.quickCapture))
        // Releasing an already-finished claim is a no-op against the newer lease.
        admission.release(first)
        #expect(admission.claim(.noteAppend(UUID())) == nil)
        admission.release(second)
        #expect(admission.claim(.dictation)?.route == .dictation)
    }

    private func makeContextEngine() -> (
        contextEngine: ContextEngineService,
        mockAXProvider: MockAXProvider,
        fakeAppElement: AXUIElement,
        fakeFocusedWindow: AXUIElement,
        fakeFocusedElement: AXUIElement
    ) {
        let mockAXProvider = MockAXProvider()
        let fakeAppElement = AXUIElementCreateApplication(88880)
        let fakeFocusedWindow = AXUIElementCreateApplication(88881)
        let fakeFocusedElement = AXUIElementCreateApplication(88882)

        mockAXProvider.frontmostAppElement = fakeAppElement
        mockAXProvider.frontmostPID = 88880
        mockAXProvider.isTrusted = true

        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Xcode")
        mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fakeAppElement, value: fakeFocusedWindow)
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeFocusedWindow, value: "AppCoordinator.swift")
        mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fakeFocusedElement, value: "AXTextArea")
        mockAXProvider.setStringAttribute(kAXSelectedTextAttribute, of: fakeFocusedElement, value: "func startRecording()")

        return (
            ContextEngineService(axProvider: mockAXProvider),
            mockAXProvider,
            fakeAppElement,
            fakeFocusedWindow,
            fakeFocusedElement
        )
    }

    @Test func enhancementUsesContextEngineSnapshot() throws {
        let fixture = makeContextEngine()
        let result = fixture.contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: nil,
            warnings: result.warnings
        )

        let ctx = try #require(snapshot.appContext)
        #expect(snapshot.warnings.isEmpty)
        #expect(snapshot.hasAnyContext)
        #expect(ctx.windowTitle == "AppCoordinator.swift")
        #expect(ctx.focusedElementRole == "AXTextArea")
        #expect(ctx.selectedText == "func startRecording()")
        #expect(ctx.hasDetailedContext)

        let legacy = snapshot.asCapturedContext
        #expect(legacy.clipboardText == nil)

        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false) == false)
    }

    @Test func contextTimeoutFallsBackWithoutBlockingTranscription() {
        let fixture = makeContextEngine()
        fixture.mockAXProvider.isTrusted = false

        let result = fixture.contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: "some clipboard text",
            warnings: result.warnings
        )

        #expect(snapshot.warnings.contains(.accessibilityPermissionDenied))
        #expect(snapshot.hasAnyContext)
        #expect(snapshot.clipboardText == "some clipboard text")

        let legacy = snapshot.asCapturedContext
        #expect(legacy.clipboardText == "some clipboard text")
    }

    @Test func escapeSuppressionOnlyWhenRecordingOrProcessing() {
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: true))
        #expect(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false) == false)
    }

    @Test func singleEscapeCancelsActiveSessionsAndNoOpsWhenIdle() {
        #expect(AppCoordinator.shouldCancelOperationOnEscape(isRecording: true, isProcessing: false))
        #expect(AppCoordinator.shouldCancelOperationOnEscape(isRecording: false, isProcessing: true))
        #expect(AppCoordinator.shouldCancelOperationOnEscape(isRecording: true, isProcessing: true))
        #expect(AppCoordinator.shouldCancelOperationOnEscape(isRecording: false, isProcessing: false) == false)

        // Suppression and cancellation share the active-session predicate so Escape is
        // swallowed only when a cancel will run.
        for recording in [false, true] {
            for processing in [false, true] {
                #expect(
                    AppCoordinator.shouldSuppressEscapeEvent(isRecording: recording, isProcessing: processing)
                        == AppCoordinator.shouldCancelOperationOnEscape(isRecording: recording, isProcessing: processing)
                )
            }
        }
    }

    @Test func dictationOperationControllerInvalidatesCancelledGeneration() {
        let controller = DictationOperationController()
        let first = controller.begin()
        #expect(controller.isCurrent(first))

        let second = controller.begin()
        #expect(controller.isCurrent(second))
        #expect(controller.isCurrent(first) == false)

        controller.cancel()
        #expect(controller.isCurrent(second) == false)

        let third = controller.begin()
        #expect(controller.isCurrent(third))
        #expect(controller.isCurrent(second) == false)
    }

    @Test func productionCleanupSkipsResetWhenOperationSupersededAfterCancel() {
        // Production stop paths defer through shouldResetProcessingStateOnExit.
        // After cancel invalidates the operation token, a stale cancelled stop must
        // not run resetProcessingState and wipe a newly started recording.
        #expect(
            AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: false,
                isOperationCurrent: true
            )
        )
        #expect(
            AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: false,
                isOperationCurrent: false
            ) == false
        )
        #expect(
            AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: true,
                isOperationCurrent: true
            ) == false
        )

        let controller = DictationOperationController()
        let stale = controller.begin()
        controller.cancel() // cancelCurrentOperation advances generation
        let next = controller.begin()
        #expect(controller.isCurrent(stale) == false)
        #expect(controller.isCurrent(next))
        #expect(
            AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: false,
                isOperationCurrent: controller.isCurrent(stale)
            ) == false
        )
        #expect(
            AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: false,
                isOperationCurrent: controller.isCurrent(next)
            )
        )
    }

    @Test func staleOrdinaryErrorDoesNotEmitFailureSideEffects() {
        // Ordinary backend errors that complete after cancel must not toast/reset.
        let controller = DictationOperationController()
        let token = controller.begin()
        controller.cancel()
        #expect(controller.isCurrent(token) == false)

        struct BackendError: Error {}
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: controller.isCurrent(token),
                error: BackendError()
            ) == false
        )
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: true,
                error: BackendError()
            )
        )
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: true,
                error: CancellationError()
            ) == false
        )
    }

    @Test func staleManualCatchMustNotMutateReplacementRecordingState() {
        // Manual path catch previously always clearCurrentJob/failCurrentJob.
        // After cancel + new claim, stale completion must skip RecordingState mutation.
        let controller = DictationOperationController()
        let admission = RecordingStopAdmission()

        let firstToken = controller.begin()
        let firstClaim = admission.claim(.manualTranscription)
        #expect(firstClaim != nil)

        // Cancel operation and free admission so a newer manual job can start.
        controller.cancel()
        admission.invalidateCurrentClaim()
        #expect(controller.isCurrent(firstToken) == false)

        let secondToken = controller.begin()
        let secondClaim = admission.claim(.manualTranscription)
        #expect(secondClaim != nil)
        #expect(controller.isCurrent(secondToken))

        // Stale first catch side effects are forbidden.
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: controller.isCurrent(firstToken),
                error: CancellationError()
            ) == false
        )
        struct BackendError: Error {}
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: controller.isCurrent(firstToken),
                error: BackendError()
            ) == false
        )
        // Current job may still emit failure side effects.
        #expect(
            AppCoordinator.shouldEmitOperationFailureSideEffects(
                isOperationCurrent: controller.isCurrent(secondToken),
                error: BackendError()
            )
        )

        // Stale deferred release cannot clear the newer claim.
        if let firstClaim {
            admission.release(firstClaim)
        }
        #expect(admission.claim(.dictation) == nil)
        if let secondClaim {
            admission.release(secondClaim)
        }
    }

    @Test func cancelledGenerationDiscardsPostAwaitOutputAndPersistSideEffects() async {
        // Production stop paths check operationController.isCurrent(token) after every
        // await before output/history. Cancel advances generation so a late backend
        // completion cannot paste/save.
        let controller = DictationOperationController()
        let token = controller.begin()

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
                await withCheckedContinuation { waiters.append($0) }
            }
        }
        actor SideEffects {
            private(set) var didOutput = false
            private(set) var didPersist = false
            private(set) var didReset = false
            func markOutput() { didOutput = true }
            func markPersist() { didPersist = true }
            func markReset() { didReset = true }
        }

        let gate = Gate()
        let effects = SideEffects()
        let processing = Task {
            await gate.waitUntilOpen()
            // Post-await ownership check (production ensureOperationCurrent equivalent).
            guard controller.isCurrent(token) else {
                // Deferred cleanup also checks ownership before resetProcessingState.
                if AppCoordinator.shouldResetProcessingStateOnExit(
                    didResetProcessingState: false,
                    isOperationCurrent: controller.isCurrent(token)
                ) {
                    await effects.markReset()
                }
                return
            }
            await effects.markOutput()
            await effects.markPersist()
            if AppCoordinator.shouldResetProcessingStateOnExit(
                didResetProcessingState: false,
                isOperationCurrent: controller.isCurrent(token)
            ) {
                await effects.markReset()
            }
        }

        controller.cancel()
        await gate.open()
        await processing.value

        #expect(await effects.didOutput == false)
        #expect(await effects.didPersist == false)
        #expect(await effects.didReset == false)
        #expect(controller.isCurrent(token) == false)
        #expect(AppCoordinator.isTaskCancellation(CancellationError()))
        #expect(AppCoordinator.isTaskCancellation(URLError(.cancelled)))
    }

    @Test func eventTapRecoveryReenablesForFirstDisableInWindow() {
        let now = Date()

        let decision = AppCoordinator.determineEventTapRecovery(
            now: now,
            lastDisableAt: now.addingTimeInterval(-0.2),
            consecutiveDisableCount: 1,
            disableLoopWindow: 1.0,
            maxReenableAttemptsBeforeRecreate: 3
        )

        #expect(decision.consecutiveDisableCount == 2)
        #expect(decision.action == .reenable)
    }

    @Test func eventTapRecoveryRecreatesAfterRepeatedDisablesInWindow() {
        let now = Date()

        let decision = AppCoordinator.determineEventTapRecovery(
            now: now,
            lastDisableAt: now.addingTimeInterval(-0.15),
            consecutiveDisableCount: 2,
            disableLoopWindow: 1.0,
            maxReenableAttemptsBeforeRecreate: 3
        )

        #expect(decision.consecutiveDisableCount == 3)
        #expect(decision.action == .recreate)
    }

    @Test func eventTapRecoveryResetsDisableBurstOutsideWindow() {
        let now = Date()

        let decision = AppCoordinator.determineEventTapRecovery(
            now: now,
            lastDisableAt: now.addingTimeInterval(-1.5),
            consecutiveDisableCount: 5,
            disableLoopWindow: 1.0,
            maxReenableAttemptsBeforeRecreate: 3
        )

        #expect(decision.consecutiveDisableCount == 1)
        #expect(decision.action == .reenable)
    }

    @Test func normalizedTranscriptionTextTrimsWhitespaceAndNewlines() {
        #expect(AppCoordinator.normalizedTranscriptionText("  hello world \n") == "hello world")
        #expect(AppCoordinator.normalizedTranscriptionText("\n\t  ") == "")
    }

    @Test func isTranscriptionEffectivelyEmptyTreatsBlankAudioPlaceholderAsEmpty() {
        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty(""))
        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty("   \n\t"))
        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty("[BLANK AUDIO]"))
        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty("  [blank audio]  "))

        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty("[BLANK AUDIO] detected speech") == false)
        #expect(AppCoordinator.isTranscriptionEffectivelyEmpty("transcribed text") == false)
    }

    @Test func shouldPersistHistoryRequiresSuccessfulOutputAndNonEmptyText() {
        #expect(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "transcribed text"))

        #expect(AppCoordinator.shouldPersistHistory(outputSucceeded: false, text: "transcribed text") == false)
        #expect(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "   ") == false)
        #expect(AppCoordinator.shouldPersistHistory(outputSucceeded: true, text: "[BLANK AUDIO]") == false)
    }

    @Test func whisperRepairSkipsDirectNetworkErrors() {
        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: URLError(.notConnectedToInternet)) == false)
        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: URLError(.networkConnectionLost)) == false)
        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: URLError(.cannotFindHost)) == false)
    }

    @Test func whisperRepairSkipsWrappedNetworkMessages() {
        let offlineError = TranscriptionService.TranscriptionError.modelLoadFailed(
            "Download failed: The Internet connection appears to be offline."
        )
        let lostConnectionError = TranscriptionService.TranscriptionError.modelLoadFailed(
            "Download failed: The network connection was lost."
        )

        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: offlineError) == false)
        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: lostConnectionError) == false)
    }

    @Test func whisperRepairAllowsLikelyCorruptionFailures() {
        let missingModelFileError = TranscriptionService.TranscriptionError.modelLoadFailed(
            "Unable to load AudioEncoder.mlmodelc from the model folder."
        )

        #expect(AppCoordinator.shouldAttemptWhisperModelRepair(after: missingModelFileError))
    }

    @Test func shouldUseStreamingTranscriptionTruthTable() {
        // Baseline: streaming enabled, indicator available, not quick-capture → stream.
        // Output mode no longer gates — the live transcript renders in the overlay, and
        // the final text lands via output() per mode (clipboard users stream too).
        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                isQuickCaptureMode: false,
                floatingIndicatorAvailable: true
            )
        )

        // Feature flag off → no streaming.
        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: false,
                isQuickCaptureMode: false,
                floatingIndicatorAvailable: true
            ) == false
        )

        // Indicator disabled or temporarily hidden → no streaming. The overlay is the
        // only place live text can render; we never force-show UI the user suppressed,
        // so the session falls back to batch.
        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                isQuickCaptureMode: false,
                floatingIndicatorAvailable: false
            ) == false
        )

        // Quick-capture mode → never stream.
        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                isQuickCaptureMode: true,
                floatingIndicatorAvailable: true
            ) == false
        )
    }

    @Test func dictationNeverUsesSpeakerDiarization() {
        // Dictation output is a single-speaker paste; "Speaker N:" attribution is
        // reserved for meeting and media transcription jobs.
        #expect(AppCoordinator.dictationUsesSpeakerDiarization == false)
    }

    @Test func escapeCancelDecisionTruthTable() {
        let now = Date()
        let window = AppCoordinator.doubleEscapeCancelWindow

        // Single-press mode always cancels, armed or not.
        #expect(
            AppCoordinator.escapeShouldCancel(
                requiresDoublePress: false, armedAt: nil, now: now, window: window
            )
        )
        #expect(
            AppCoordinator.escapeShouldCancel(
                requiresDoublePress: false, armedAt: now.addingTimeInterval(-10), now: now, window: window
            )
        )

        // Double-press mode: first press only arms.
        #expect(
            AppCoordinator.escapeShouldCancel(
                requiresDoublePress: true, armedAt: nil, now: now, window: window
            ) == false
        )

        // Second press within the window cancels.
        #expect(
            AppCoordinator.escapeShouldCancel(
                requiresDoublePress: true,
                armedAt: now.addingTimeInterval(-window + 0.1),
                now: now,
                window: window
            )
        )

        // A stale arm outside the window does not cancel.
        #expect(
            AppCoordinator.escapeShouldCancel(
                requiresDoublePress: true,
                armedAt: now.addingTimeInterval(-window - 0.1),
                now: now,
                window: window
            ) == false
        )
    }

    @Test func floatingIndicatorFocusTrackingModeUsesIdlePillWhenIdleAlwaysOnStyles() {
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .orb,
                isRecording: false,
                isProcessing: false
            ) == .idlePill
        )
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .pill,
                isRecording: false,
                isProcessing: false
            ) == .idlePill
        )
    }

    @Test func floatingIndicatorFocusTrackingModeStopsWhenIdleTransientStyles() {
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .notch,
                isRecording: false,
                isProcessing: false
            ) == nil
        )
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .bubble,
                isRecording: false,
                isProcessing: false
            ) == nil
        )
    }

    @Test func floatingIndicatorFocusTrackingModeUsesActiveSessionWhileRecordingOrProcessing() {
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .orb,
                isRecording: true,
                isProcessing: false
            ) == .activeSession
        )

        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .notch,
                isRecording: false,
                isProcessing: true
            ) == .activeSession
        )

        // Bubble owns caret-anchor refresh itself during active sessions.
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: false,
                selectedType: .bubble,
                isRecording: true,
                isProcessing: false
            ) == nil
        )
    }

    @Test func floatingIndicatorFocusTrackingModeStopsWhenTemporarilyHidden() {
        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: true,
                selectedType: .orb,
                isRecording: true,
                isProcessing: false
            ) == nil
        )

        #expect(
            AppCoordinator.floatingIndicatorFocusTrackingMode(
                isTemporarilyHidden: true,
                selectedType: .notch,
                isRecording: false,
                isProcessing: false
            ) == nil
        )
    }
}
