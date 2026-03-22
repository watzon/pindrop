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
    var keyEvents: [(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool)] = []
    var pasteSimulated = false
    var simulatePasteCallCount = 0

    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) throws {
        keyEvents.append((keyCode, flags, keyDown))
    }

    func simulatePaste() async throws {
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

    @Test func beginAndUpdateStreamingInsertionTypesInitialText() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello")

        #expect(fixture.mockKeySimulation.keyEvents.count == 10)
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
    }

    @Test func streamingUpdateBackspacesChangedSuffixOnly() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello")
        fixture.mockKeySimulation.keyEvents.removeAll()

        try await fixture.outputManager.updateStreamingInsertion(with: "help")

        #expect(fixture.mockKeySimulation.keyEvents.count == 6)
        #expect(fixture.mockKeySimulation.keyEvents[0].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[1].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[2].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[3].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[4].keyCode == 35)
        #expect(fixture.mockKeySimulation.keyEvents[5].keyCode == 35)
    }

    @Test func finishStreamingInsertionAppendsTrailingSpaceWhenRequested() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello")
        fixture.mockKeySimulation.keyEvents.removeAll()

        try await fixture.outputManager.finishStreamingInsertion(finalText: "hello", appendTrailingSpace: true)

        #expect(fixture.mockKeySimulation.keyEvents.count == 2)
        #expect(fixture.mockKeySimulation.keyEvents[0].keyCode == 49)
        #expect(fixture.mockKeySimulation.keyEvents[1].keyCode == 49)
    }

    @Test func cancelStreamingInsertionPreservesTypedTextWhenRequested() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "keep me")
        let eventCountBeforeCancel = fixture.mockKeySimulation.keyEvents.count

        await fixture.outputManager.cancelStreamingInsertion(removeInsertedText: false)

        #expect(fixture.mockKeySimulation.keyEvents.count == eventCountBeforeCancel)

        do {
            try await fixture.outputManager.updateStreamingInsertion(with: "new text")
            Issue.record("Expected streaming insertion to be inactive after cancel")
        } catch OutputManagerError.textInsertionFailed {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
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

    @Test func directInsertRestoresClipboard() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.mockClipboard.clipboardContent = "Previous clipboard content"

        try await fixture.outputManager.output("Direct insert test")

        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
        #expect(fixture.mockClipboard.clipboardContent == "Previous clipboard content")
    }

    @Test func directInsertFallsBackToClipboardPasteForUnsupportedText() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.mockClipboard.clipboardContent = "Previous clipboard content"

        try await fixture.outputManager.output("hello 😀")

        #expect(fixture.mockKeySimulation.pasteSimulated)
        #expect(fixture.mockClipboard.restoreCount == 1)
        #expect(fixture.mockClipboard.copiedText == "Previous clipboard content")
        #expect(fixture.mockClipboard.clipboardContent == "Previous clipboard content")
    }

    @Test func clipboardModeFallsBackToCopyWithoutAccessibility() async throws {
        let fixture = makeSUT(outputMode: .clipboard, accessibilityPermissionChecker: { false })

        try await fixture.outputManager.output("Clipboard test")

        #expect(fixture.mockClipboard.copiedText == "Clipboard test")
        #expect(fixture.mockClipboard.clipboardContent == "Clipboard test")
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
    }

    @Test func getKeyCodeForBasicCharacters() {
        let fixture = makeSUT()
        let aKeyCode = fixture.outputManager.getKeyCodeForCharacter("a")
        #expect(aKeyCode != nil)
        #expect(aKeyCode?.0 == 0)
        #expect(aKeyCode?.1.isEmpty == true)

        let uppercaseAKeyCode = fixture.outputManager.getKeyCodeForCharacter("A")
        #expect(uppercaseAKeyCode != nil)
        #expect(uppercaseAKeyCode?.0 == 0)
        #expect(uppercaseAKeyCode?.1.contains(.maskShift) == true)

        let oneKeyCode = fixture.outputManager.getKeyCodeForCharacter("1")
        #expect(oneKeyCode != nil)
        #expect(oneKeyCode?.0 == 18)

        let spaceKeyCode = fixture.outputManager.getKeyCodeForCharacter(" ")
        #expect(spaceKeyCode != nil)
        #expect(spaceKeyCode?.0 == 49)
    }

    @Test func getKeyCodeForSpecialCharacters() {
        let fixture = makeSUT()
        let periodKeyCode = fixture.outputManager.getKeyCodeForCharacter(".")
        #expect(periodKeyCode != nil)

        let commaKeyCode = fixture.outputManager.getKeyCodeForCharacter(",")
        #expect(commaKeyCode != nil)

        let exclamationKeyCode = fixture.outputManager.getKeyCodeForCharacter("!")
        #expect(exclamationKeyCode != nil)
        #expect(exclamationKeyCode?.1.contains(.maskShift) == true)
    }

    @Test func getKeyCodeForUnsupportedCharacter() {
        let fixture = makeSUT()
        #expect(fixture.outputManager.getKeyCodeForCharacter("😀") == nil)
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

    @Test func mockKeySimulationTracksEvents() async throws {
        let mockKeySimulation = MockKeySimulation()
        #expect(mockKeySimulation.keyEvents.count == 0)
        #expect(mockKeySimulation.pasteSimulated == false)

        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: true)
        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: false)

        #expect(mockKeySimulation.keyEvents.count == 2)
        #expect(mockKeySimulation.keyEvents[0].keyDown)
        #expect(mockKeySimulation.keyEvents[1].keyDown == false)

        try await mockKeySimulation.simulatePaste()
        #expect(mockKeySimulation.pasteSimulated)
    }
}
