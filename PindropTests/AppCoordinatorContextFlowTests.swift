//
//  AppCoordinatorContextFlowTests.swift
//  PindropTests
//
//  Created on 2026-02-09.
//

import ApplicationServices
import XCTest

@testable import Pindrop

@MainActor
final class AppCoordinatorContextFlowTests: XCTestCase {

    var contextEngine: ContextEngineService!
    var mockAXProvider: MockAXProvider!
    var fakeAppElement: AXUIElement!
    var fakeFocusedWindow: AXUIElement!
    var fakeFocusedElement: AXUIElement!

    override func setUp() async throws {
        mockAXProvider = MockAXProvider()
        fakeAppElement = AXUIElementCreateApplication(88880)
        fakeFocusedWindow = AXUIElementCreateApplication(88881)
        fakeFocusedElement = AXUIElementCreateApplication(88882)

        mockAXProvider.frontmostAppElement = fakeAppElement
        mockAXProvider.frontmostPID = 88880
        mockAXProvider.isTrusted = true

        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeAppElement, value: "Xcode")
        mockAXProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fakeAppElement, value: fakeFocusedWindow)
        mockAXProvider.setStringAttribute(kAXTitleAttribute, of: fakeFocusedWindow, value: "AppCoordinator.swift")
        mockAXProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fakeAppElement, value: fakeFocusedElement)
        mockAXProvider.setStringAttribute(kAXRoleAttribute, of: fakeFocusedElement, value: "AXTextArea")
        mockAXProvider.setStringAttribute(kAXSelectedTextAttribute, of: fakeFocusedElement, value: "func startRecording()")

        contextEngine = ContextEngineService(axProvider: mockAXProvider)
    }

    override func tearDown() async throws {
        contextEngine = nil
        mockAXProvider = nil
        fakeAppElement = nil
        fakeFocusedWindow = nil
        fakeFocusedElement = nil
    }

    // MARK: - Tests

    func testEnhancementUsesContextEngineSnapshot() {
        let result = contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: nil,
            warnings: result.warnings
        )

        XCTAssertNotNil(snapshot.appContext, "Snapshot should contain app context when AX is trusted")
        XCTAssertTrue(snapshot.warnings.isEmpty, "No warnings expected for trusted AX capture")
        XCTAssertTrue(snapshot.hasAnyContext, "Snapshot should report having context")

        let ctx = snapshot.appContext!
        XCTAssertEqual(ctx.windowTitle, "AppCoordinator.swift")
        XCTAssertEqual(ctx.focusedElementRole, "AXTextArea")
        XCTAssertEqual(ctx.selectedText, "func startRecording()")
        XCTAssertTrue(ctx.hasDetailedContext, "Context with window title and selected text should be detailed")

        let legacy = snapshot.asCapturedContext
        XCTAssertNil(legacy.clipboardText, "Legacy bridge should have nil clipboard text when not captured")

        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        XCTAssertFalse(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false))

        let now = Date()
        XCTAssertTrue(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.2),
                threshold: 0.4
            )
        )
        XCTAssertFalse(
            AppCoordinator.isDoubleEscapePress(
                now: now,
                lastEscapeTime: now.addingTimeInterval(-0.6),
                threshold: 0.4
            )
        )
    }

    func testContextTimeoutFallsBackWithoutBlockingTranscription() {
        mockAXProvider.isTrusted = false

        let result = contextEngine.captureAppContext()

        let snapshot = ContextSnapshot(
            timestamp: Date(),
            appContext: result.appContext,
            clipboardText: "some clipboard text",
            warnings: result.warnings
        )

        XCTAssertTrue(
            snapshot.warnings.contains(.accessibilityPermissionDenied),
            "Should have accessibility permission denied warning"
        )
        XCTAssertTrue(snapshot.hasAnyContext, "Snapshot should still report context from clipboard")
        XCTAssertEqual(snapshot.clipboardText, "some clipboard text", "Clipboard text should be preserved")

        let legacy = snapshot.asCapturedContext
        XCTAssertEqual(legacy.clipboardText, "some clipboard text", "Legacy bridge should preserve clipboard text")
    }

    func testEscapeSuppressionOnlyWhenRecordingOrProcessing() {
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: false))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: true))
        XCTAssertTrue(AppCoordinator.shouldSuppressEscapeEvent(isRecording: true, isProcessing: true))
        XCTAssertFalse(AppCoordinator.shouldSuppressEscapeEvent(isRecording: false, isProcessing: false))
    }

    func testDoubleEscapeDetectionHonorsThreshold() {
        let now = Date()
        let withinThreshold = now.addingTimeInterval(-0.25)
        let outsideThreshold = now.addingTimeInterval(-0.6)

        XCTAssertTrue(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: withinThreshold, threshold: 0.4))
        XCTAssertFalse(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: outsideThreshold, threshold: 0.4))
        XCTAssertFalse(AppCoordinator.isDoubleEscapePress(now: now, lastEscapeTime: nil, threshold: 0.4))
    }
}
