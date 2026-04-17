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
    var characterEvents: [(character: Character, keyDown: Bool)] = []
    var pasteSimulated = false
    var simulatePasteCallCount = 0

    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) throws {
        keyEvents.append((keyCode, flags, keyDown))
    }

    func postCharacterEvent(character: Character, keyDown: Bool) throws {
        characterEvents.append((character, keyDown))
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

        #expect(fixture.mockKeySimulation.characterEvents.count == 10)
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
    }

    @Test func streamingUpdateBackspacesChangedSuffixOnly() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello")
        fixture.mockKeySimulation.keyEvents.removeAll()
        fixture.mockKeySimulation.characterEvents.removeAll()

        try await fixture.outputManager.updateStreamingInsertion(with: "help")

        #expect(fixture.mockKeySimulation.keyEvents.count == 4)
        #expect(fixture.mockKeySimulation.keyEvents[0].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[1].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[2].keyCode == 51)
        #expect(fixture.mockKeySimulation.keyEvents[3].keyCode == 51)
        #expect(fixture.mockKeySimulation.characterEvents.count == 2)
        #expect(fixture.mockKeySimulation.characterEvents[0].character == "p")
        #expect(fixture.mockKeySimulation.characterEvents[1].character == "p")
    }

    // Regression test — interior character diff (the case AI refinement produces).
    //
    // Previous implementation of longestCommonPrefixLength used `where left == right` as a
    // filter across all zipped pairs, which kept counting matches *after* a divergence.
    // That over-counted the "common prefix" and caused OutputManager to delete too few
    // characters and insert a truncated suffix, producing visible corruption like "see"
    // → "sseeee" when refinement swapped a word mid-string. The fixed implementation
    // stops at the first mismatch.
    @Test func streamingUpdateHandlesInteriorCharacterSwap() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello world")
        fixture.mockKeySimulation.keyEvents.removeAll()
        fixture.mockKeySimulation.characterEvents.removeAll()

        // Interior swap: 'e' → 'a' at offset 1. True common prefix is just "h" (1 char).
        // Buggy prefix function would have counted all matching positions after the
        // divergence and returned 10, under-deleting.
        try await fixture.outputManager.updateStreamingInsertion(with: "hallo world")

        // Expect 10 backspaces (11 chars - 1 prefix "h"). deleteBackward emits 2 key events
        // per backspace (down + up), so 20 total.
        #expect(fixture.mockKeySimulation.keyEvents.count == 20)
        for event in fixture.mockKeySimulation.keyEvents {
            #expect(event.keyCode == 51)
        }
        // characterEvents also contains down + up per char, so 10 chars → 20 events.
        let inserted = fixture.mockKeySimulation.characterEvents.map { String($0.character) }
        #expect(inserted.count == 20)
        let typed = stride(from: 0, to: inserted.count, by: 2).map { inserted[$0] }.joined()
        #expect(typed == "allo world")
    }

    // Regression test — AI refinement of an earlier word. Mirrors the exact user-reported
    // symptom where "see" was corrupted into "sseeee" by the prefix bug.
    @Test func streamingUpdateReplacesMidTranscriptWord() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(
            with: "this is a test of real time transcription to see")
        fixture.mockKeySimulation.keyEvents.removeAll()
        fixture.mockKeySimulation.characterEvents.removeAll()

        // Refinement keeps most of the prefix but capitalizes and cleans the tail.
        try await fixture.outputManager.updateStreamingInsertion(
            with: "This is a test of real-time transcription to see")

        // Common prefix is empty (first char flips from 't' to 'T'), so we delete all 48
        // previous chars and retype 48 new ones. 2 events per backspace + 2 events per
        // character = 96 keyEvents and 96 characterEvents.
        #expect(fixture.mockKeySimulation.keyEvents.count == 96)
        let deleted = fixture.mockKeySimulation.keyEvents.allSatisfy { $0.keyCode == 51 }
        #expect(deleted)
        let charEvents = fixture.mockKeySimulation.characterEvents
        let typed = stride(from: 0, to: charEvents.count, by: 2)
            .map { String(charEvents[$0].character) }.joined()
        #expect(typed == "This is a test of real-time transcription to see")
    }

    // Regression — concurrent streaming writes must serialize. Before the fix, two
    // in-flight updateStreamingInsertion calls read the same stale `lastStreamingText`
    // baseline and interleaved their keystrokes, producing corruption like "sseeee" or
    // "lives stuff" re-introducing characters a prior refinement had removed.
    //
    // This test fires three updates in rapid succession with different targets and
    // verifies that (a) the final `lastStreamingText` matches the last call's target,
    // and (b) the total character events sequence reflects a clean diff from empty to
    // the final target — no cross-contamination from intermediate states.
    @Test func concurrentStreamingWritesSerialize() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        // Kick off three writes without awaiting the first two individually. Each grows
        // the text; with serialization, the final lastStreamingText must be the third
        // target, and the keystroke stream must produce exactly that string.
        async let t1: Void = fixture.outputManager.updateStreamingInsertion(with: "hello")
        async let t2: Void = fixture.outputManager.updateStreamingInsertion(with: "hello world")
        async let t3: Void = fixture.outputManager.updateStreamingInsertion(with: "hello world!")
        _ = try await (t1, t2, t3)

        // Typed-character stream (filter keyDown events — each char produces a down+up
        // pair, so iterate stride 2). Must spell exactly "hello world!" after accounting
        // for any intermediate deletes.
        let charEvents = fixture.mockKeySimulation.characterEvents
        let downs = stride(from: 0, to: charEvents.count, by: 2)
            .map { String(charEvents[$0].character) }
            .joined()

        // With correct serialization, each write only types its incremental suffix.
        // Write 1: types "hello" (5 chars)
        // Write 2: types " world" (6 chars) — prefix "hello" matched, no deletes
        // Write 3: types "!" (1 char) — prefix "hello world" matched, no deletes
        // Total typed chars = 12, no deletes.
        #expect(downs == "hello world!")
        #expect(fixture.mockKeySimulation.keyEvents.isEmpty)  // no backspaces
    }

    @Test func finishStreamingInsertionAppendsTrailingSpaceWhenRequested() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "hello")
        fixture.mockKeySimulation.characterEvents.removeAll()

        try await fixture.outputManager.finishStreamingInsertion(finalText: "hello", appendTrailingSpace: true)

        #expect(fixture.mockKeySimulation.characterEvents.count == 2)
        #expect(fixture.mockKeySimulation.characterEvents[0].character == " ")
        #expect(fixture.mockKeySimulation.characterEvents[1].character == " ")
    }

    @Test func cancelStreamingInsertionPreservesTypedTextWhenRequested() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.outputManager.beginStreamingInsertion()

        try await fixture.outputManager.updateStreamingInsertion(with: "keep me")
        let charEventCountBeforeCancel = fixture.mockKeySimulation.characterEvents.count

        await fixture.outputManager.cancelStreamingInsertion(removeInsertedText: false)

        #expect(fixture.mockKeySimulation.characterEvents.count == charEventCountBeforeCancel)

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

    @Test func directInsertHandlesEmojiWithoutClipboardFallback() async throws {
        let fixture = makeSUT(outputMode: .directInsert)
        fixture.mockClipboard.clipboardContent = "Previous clipboard content"

        try await fixture.outputManager.output("hello 😀")

        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
        #expect(fixture.mockClipboard.clipboardContent == "Previous clipboard content")
        #expect(fixture.mockKeySimulation.characterEvents.count == 14)
    }

    @Test func clipboardModeFallsBackToCopyWithoutAccessibility() async throws {
        let fixture = makeSUT(outputMode: .clipboard, accessibilityPermissionChecker: { false })

        try await fixture.outputManager.output("Clipboard test")

        #expect(fixture.mockClipboard.copiedText == "Clipboard test")
        #expect(fixture.mockClipboard.clipboardContent == "Clipboard test")
        #expect(fixture.mockKeySimulation.pasteSimulated == false)
        #expect(fixture.mockClipboard.restoreCount == 0)
    }

    @Test func directInsertTypesCharactersViaUnicode() async throws {
        let fixture = makeSUT(outputMode: .directInsert)

        try await fixture.outputManager.output("Hi!")

        #expect(fixture.mockKeySimulation.characterEvents.count == 6)
        #expect(fixture.mockKeySimulation.characterEvents[0].character == "H")
        #expect(fixture.mockKeySimulation.characterEvents[0].keyDown == true)
        #expect(fixture.mockKeySimulation.characterEvents[1].character == "H")
        #expect(fixture.mockKeySimulation.characterEvents[1].keyDown == false)
        #expect(fixture.mockKeySimulation.characterEvents[2].character == "i")
        #expect(fixture.mockKeySimulation.characterEvents[4].character == "!")
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
        #expect(mockKeySimulation.characterEvents.count == 0)
        #expect(mockKeySimulation.pasteSimulated == false)

        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: true)
        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: false)

        #expect(mockKeySimulation.keyEvents.count == 2)
        #expect(mockKeySimulation.keyEvents[0].keyDown)
        #expect(mockKeySimulation.keyEvents[1].keyDown == false)

        try mockKeySimulation.postCharacterEvent(character: "a", keyDown: true)
        #expect(mockKeySimulation.characterEvents.count == 1)
        #expect(mockKeySimulation.characterEvents[0].character == "a")

        try await mockKeySimulation.simulatePaste()
        #expect(mockKeySimulation.pasteSimulated)
    }
}
