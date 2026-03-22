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

        let now = Date()
        #expect(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.2),
                threshold: 0.4
            )
        )
        #expect(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.6),
                threshold: 0.4
            ) == false
        )
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

    @Test func doubleEscapeDetectionHonorsThreshold() {
        let now = Date()
        let withinThreshold = now.addingTimeInterval(-0.25)
        let outsideThreshold = now.addingTimeInterval(-0.6)

        #expect(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: withinThreshold, threshold: 0.4))
        #expect(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: outsideThreshold, threshold: 0.4) == false)
        #expect(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: nil, threshold: 0.4) == false)
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

    @Test func shouldUseStreamingTranscriptionTruthTable() {
        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                outputMode: .directInsert,
                aiEnhancementEnabled: false,
                isQuickCaptureMode: false
            )
        )

        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: false,
                outputMode: .directInsert,
                aiEnhancementEnabled: false,
                isQuickCaptureMode: false
            ) == false
        )

        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                outputMode: .clipboard,
                aiEnhancementEnabled: false,
                isQuickCaptureMode: false
            ) == false
        )

        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                outputMode: .directInsert,
                aiEnhancementEnabled: true,
                isQuickCaptureMode: false
            ) == false
        )

        #expect(
            AppCoordinator.shouldUseStreamingTranscription(
                streamingFeatureEnabled: true,
                outputMode: .directInsert,
                aiEnhancementEnabled: false,
                isQuickCaptureMode: true
            ) == false
        )
    }

    @Test func shouldUseSpeakerDiarizationTruthTable() {
        #expect(
            AppCoordinator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled: true,
                isStreamingSessionActive: false
            )
        )

        #expect(
            AppCoordinator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled: false,
                isStreamingSessionActive: false
            ) == false
        )

        #expect(
            AppCoordinator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled: true,
                isStreamingSessionActive: true
            ) == false
        )

        #expect(
            AppCoordinator.shouldUseSpeakerDiarization(
                diarizationFeatureEnabled: false,
                isStreamingSessionActive: true
            ) == false
        )
    }
}
