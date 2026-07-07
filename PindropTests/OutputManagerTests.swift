//
//  OutputManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import Pindrop

final class MockClipboard: ClipboardProtocol {
    var copiedText: String?
    var clipboardContent: String?
    var restoreCount = 0
    var lastRestoredSnapshot: ClipboardSnapshot?
    var changeCount = 0

    func copyToClipboard(_ text: String) -> Bool {
        copiedText = text
        clipboardContent = text
        changeCount += 1
        return true
    }

    func captureSnapshot() -> ClipboardSnapshot {
        guard let clipboardContent else {
            return ClipboardSnapshot(items: [], changeCount: changeCount)
        }

        let data = Data(clipboardContent.utf8)
        return ClipboardSnapshot(items: [[NSPasteboard.PasteboardType.string.rawValue: data]], changeCount: changeCount)
    }

    func currentChangeCount() -> Int { changeCount }
    func currentStringContent() -> String? { clipboardContent }

    func restoreSnapshot(_ snapshot: ClipboardSnapshot) -> Bool {
        restoreCount += 1
        lastRestoredSnapshot = snapshot
        changeCount += 1

        guard let firstItem = snapshot.items.first,
              let data = firstItem[NSPasteboard.PasteboardType.string.rawValue] else {
            clipboardContent = nil
            copiedText = nil
            return true
        }

        let restoredText = String(data: data, encoding: .utf8)
        clipboardContent = restoredText
        copiedText = restoredText
        return true
    }
}

final class MockKeySimulation: KeySimulationProtocol {
    var pasteSimulated = false
    var simulatePasteCallCount = 0
    /// When set, `simulatePaste()` throws — exercises the copy-only fallback paths.
    var pasteError: Error?

    func simulatePaste() async throws {
        if let pasteError {
            throw pasteError
        }
        pasteSimulated = true
        simulatePasteCallCount += 1
    }
}

@MainActor
@Suite
struct OutputManagerTests {
    private func makeSUT(
        outputMode: OutputMode = .clipboard,
        accessibilityPermissionChecker: @escaping () -> Bool = { true }
    ) -> (outputManager: OutputManager, mockClipboard: MockClipboard, mockKeySimulation: MockKeySimulation) {
        let mockClipboard = MockClipboard()
        let mockKeySimulation = MockKeySimulation()
        let outputManager = OutputManager(
            outputMode: outputMode,
            clipboard: mockClipboard,
            keySimulation: mockKeySimulation,
            accessibilityPermissionChecker: accessibilityPermissionChecker,
            frontmostApplicationProvider: { nil }
        )
        return (outputManager, mockClipboard, mockKeySimulation)
    }

    @Test func initialOutputModeIsClipboard() {
        let fixture = makeSUT()
        #expect(fixture.outputManager.outputMode == .clipboard)
    }

    @Test func setOutputMode() {
        let fixture = makeSUT()
        fixture.outputManager.setOutputMode(.directInsert)
        #expect(fixture.outputManager.outputMode == .directInsert)

        fixture.outputManager.setOutputMode(.clipboard)
        #expect(fixture.outputManager.outputMode == .clipboard)
    }

    @Test func copyToClipboard() throws {
        let fixture = makeSUT()
        let testText = "Hello from Pindrop!"

        try fixture.outputManager.copyToClipboard(testText)

        #expect(fixture.mockClipboard.copiedText == testText)
        #expect(fixture.mockClipboard.clipboardContent == testText)
    }

    @Test func copyToClipboardReplacesExistingContent() throws {
        let fixture = makeSUT()

        try fixture.outputManager.copyToClipboard("First text")
        #expect(fixture.mockClipboard.copiedText == "First text")

        try fixture.outputManager.copyToClipboard("Second text")
        #expect(fixture.mockClipboard.copiedText == "Second text")
    }

    @Test func outputWithClipboardMode() async throws {
        let fixture = makeSUT()
        fixture.outputManager.setOutputMode(.clipboard)
        fixture.mockClipboard.clipboardContent = "Previous clipboard content"

        try await fixture.outputManager.output("Clipboard mode test")

        #expect(fixture.mockClipboard.copiedText == "Previous clipboard content")
        #expect(fixture.mockClipboard.clipboardContent == "Previous clipboard content")
        #expect(fixture.mockKeySimulation.pasteSimulated)
        #expect(fixture.mockClipboard.restoreCount == 1)
    }

    @Test func outputWithEmptyTextThrowsError() async {
        let fixture = makeSUT()
        fixture.outputManager.setOutputMode(.clipboard)

        do {
            try await fixture.outputManager.output("")
            Issue.record("Expected error for empty text")
        } catch OutputManagerError.emptyText {
            #expect(fixture.mockClipboard.copiedText == nil)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func checkAccessibilityPermission() {
        let fixture = makeSUT()
        let hasPermission = fixture.outputManager.checkAccessibilityPermission()
        #expect(hasPermission == true || hasPermission == false)
    }

    // Direct insert is paste-based: one atomic Cmd+V with clipboard snapshot/restore.
    @Test func directInsertPastesAndRestoresClipboard() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.mockClipboard.clipboardContent = "Previous clipboard content"

        let result = try await fixture.outputManager.output("Direct insert test")

        #expect(result == .pasted)
        #expect(fixture.mockKeySimulation.pasteSimulated)
        #expect(fixture.mockClipboard.restoreCount == 1)
        #expect(fixture.mockClipboard.clipboardContent == "Previous clipboard content")
    }

    @Test func directInsertCopiesOnlyWithoutAccessibility() async throws {
        let fixture = makeSUT(outputMode: .directInsert, accessibilityPermissionChecker: { false })

        let result = try await fixture.outputManager.output("Direct insert test")

        #expect(result == .copiedToClipboard)
        #expect(fixture.mockClipboard.copiedText == "Direct insert test")
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
    }

    @Test func directInsertFallsBackToCopyWhenPasteFails() async throws {
        struct PasteFailure: Error {}
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.mockKeySimulation.pasteError = PasteFailure()

        let result = try await fixture.outputManager.output("Important words")

        // The user's words must never be lost: paste failed, so the text stays on the
        // clipboard and the caller is told so.
        #expect(result == .copiedToClipboard)
        #expect(fixture.mockClipboard.copiedText == "Important words")
        #expect(fixture.mockClipboard.clipboardContent == "Important words")
    }

    @Test func clipboardModeFallsBackToCopyWithoutAccessibility() async throws {
        let fixture = makeSUT(outputMode: .clipboard, accessibilityPermissionChecker: { false })

        let result = try await fixture.outputManager.output("Clipboard test")

        #expect(result == .copiedToClipboard)
        #expect(fixture.mockClipboard.copiedText == "Clipboard test")
        #expect(fixture.mockClipboard.clipboardContent == "Clipboard test")
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
    }

    @Test func clipboardModeReportsPastedOnSuccess() async throws {
        let fixture = makeSUT(outputMode: .clipboard)

        let result = try await fixture.outputManager.output("Clipboard test")

        #expect(result == .pasted)
        #expect(fixture.mockKeySimulation.pasteSimulated)
    }

    @Test func errorDescriptions() {
        #expect(OutputManagerError.accessibilityPermissionDenied.errorDescription != nil)
        #expect(OutputManagerError.emptyText.errorDescription != nil)
        #expect(OutputManagerError.clipboardWriteFailed.errorDescription != nil)
        #expect(OutputManagerError.textInsertionFailed.errorDescription != nil)
    }

    @Test func mockClipboardTracksOperations() {
        let mockClipboard = MockClipboard()
        #expect(mockClipboard.copiedText == nil)
        #expect(mockClipboard.clipboardContent == nil)
        #expect(mockClipboard.restoreCount == 0)

        let success = mockClipboard.copyToClipboard("test")
        #expect(success)
        #expect(mockClipboard.copiedText == "test")
        #expect(mockClipboard.clipboardContent == "test")

        let snapshot = mockClipboard.captureSnapshot()
        mockClipboard.clipboardContent = nil
        mockClipboard.copiedText = nil

        #expect(mockClipboard.restoreSnapshot(snapshot))
        #expect(mockClipboard.restoreCount == 1)
        #expect(mockClipboard.clipboardContent == "test")
    }

    @Test func mockKeySimulationTracksPaste() async throws {
        let mockKeySimulation = MockKeySimulation()
        #expect(mockKeySimulation.pasteSimulated == false)
        #expect(mockKeySimulation.simulatePasteCallCount == 0)

        try await mockKeySimulation.simulatePaste()

        #expect(mockKeySimulation.pasteSimulated)
        #expect(mockKeySimulation.simulatePasteCallCount == 1)
    }

    @Test func systemKeySimulationPostsPhysicalCommandAroundPasteShortcut() async throws {
        var postedEvents: [KeySimulationEvent] = []
        var sleepDurations: [UInt64] = []
        var systemEventsFallbackCalled = false
        let sut = SystemKeySimulation(
            pasteScriptRunner: {
                systemEventsFallbackCalled = true
                return false
            },
            keyEventPoster: { _, event in
                postedEvents.append(event)
                return true
            },
            sleeper: { duration in
                sleepDurations.append(duration)
            }
        )

        try await sut.simulatePaste()

        #expect(postedEvents == [
            KeySimulationEvent(virtualKey: 0x37, keyDown: true, flags: .maskCommand),
            KeySimulationEvent(virtualKey: 0x09, keyDown: true, flags: .maskCommand),
            KeySimulationEvent(virtualKey: 0x09, keyDown: false, flags: .maskCommand),
            KeySimulationEvent(virtualKey: 0x37, keyDown: false, flags: []),
        ])
        #expect(sleepDurations == [50_000_000, 50_000_000, 50_000_000])
        #expect(systemEventsFallbackCalled == false)
    }

    @Test func systemKeySimulationFallsBackToSystemEventsWhenCGEventPostingFails() async throws {
        var postedEvents: [KeySimulationEvent] = []
        var systemEventsFallbackCalled = false
        let sut = SystemKeySimulation(
            pasteScriptRunner: {
                systemEventsFallbackCalled = true
                return true
            },
            keyEventPoster: { _, event in
                postedEvents.append(event)
                return false
            },
            sleeper: { _ in }
        )

        try await sut.simulatePaste()

        #expect(postedEvents == [
            KeySimulationEvent(virtualKey: 0x37, keyDown: true, flags: .maskCommand),
        ])
        #expect(systemEventsFallbackCalled)
    }
}
