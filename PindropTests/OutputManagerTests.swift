//
//  OutputManagerTests.swift
//  PindropTests
//
//  Created on 2026-01-25.
//

import XCTest
import AppKit
import ApplicationServices
@testable import Pindrop

final class MockClipboard: ClipboardProtocol {
    var copiedText: String?
    var clipboardContent: String?
    var clearCount = 0
    
    func copyToClipboard(_ text: String) -> Bool {
        copiedText = text
        clipboardContent = text
        return true
    }
    
    func getClipboardContent() -> String? {
        return clipboardContent
    }
    
    func clearClipboard() {
        clearCount += 1
        clipboardContent = nil
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
final class OutputManagerTests: XCTestCase {
    
    var outputManager: OutputManager!
    var mockClipboard: MockClipboard!
    var mockKeySimulation: MockKeySimulation!
    
    override func setUp() async throws {
        mockClipboard = MockClipboard()
        mockKeySimulation = MockKeySimulation()
        outputManager = OutputManager(
            clipboard: mockClipboard,
            keySimulation: mockKeySimulation
        )
    }
    
    override func tearDown() async throws {
        outputManager = nil
        mockClipboard = nil
        mockKeySimulation = nil
    }
    
    func testInitialOutputModeIsClipboard() {
        XCTAssertEqual(outputManager.outputMode, .clipboard)
    }
    
    func testSetOutputMode() {
        outputManager.setOutputMode(.directInsert)
        XCTAssertEqual(outputManager.outputMode, .directInsert)
        
        outputManager.setOutputMode(.clipboard)
        XCTAssertEqual(outputManager.outputMode, .clipboard)
    }
    
    func testCopyToClipboard() throws {
        let testText = "Hello from Pindrop!"
        
        try outputManager.copyToClipboard(testText)
        
        XCTAssertEqual(mockClipboard.copiedText, testText)
        XCTAssertEqual(mockClipboard.clipboardContent, testText)
    }
    
    func testCopyToClipboardReplacesExistingContent() throws {
        let firstText = "First text"
        let secondText = "Second text"
        
        try outputManager.copyToClipboard(firstText)
        XCTAssertEqual(mockClipboard.copiedText, firstText)
        
        try outputManager.copyToClipboard(secondText)
        XCTAssertEqual(mockClipboard.copiedText, secondText)
    }
    
    func testOutputWithClipboardMode() async throws {
        outputManager.setOutputMode(.clipboard)
        let testText = "Clipboard mode test"
        
        try await outputManager.output(testText)
        
        XCTAssertEqual(mockClipboard.copiedText, testText)
        XCTAssertFalse(mockKeySimulation.pasteSimulated)
        XCTAssertEqual(mockClipboard.clearCount, 0)
    }

    func testBeginAndUpdateStreamingInsertionTypesInitialText() async throws {
        outputManager.setOutputMode(.directInsert)
        outputManager.beginStreamingInsertion()

        try await outputManager.updateStreamingInsertion(with: "hello")

        XCTAssertEqual(mockKeySimulation.keyEvents.count, 10)
        XCTAssertFalse(mockKeySimulation.pasteSimulated)
    }

    func testStreamingUpdateBackspacesChangedSuffixOnly() async throws {
        outputManager.setOutputMode(.directInsert)
        outputManager.beginStreamingInsertion()

        try await outputManager.updateStreamingInsertion(with: "hello")
        mockKeySimulation.keyEvents.removeAll()

        try await outputManager.updateStreamingInsertion(with: "help")

        XCTAssertEqual(mockKeySimulation.keyEvents.count, 6)
        XCTAssertEqual(mockKeySimulation.keyEvents[0].keyCode, 51)
        XCTAssertEqual(mockKeySimulation.keyEvents[1].keyCode, 51)
        XCTAssertEqual(mockKeySimulation.keyEvents[2].keyCode, 51)
        XCTAssertEqual(mockKeySimulation.keyEvents[3].keyCode, 51)
        XCTAssertEqual(mockKeySimulation.keyEvents[4].keyCode, 35)
        XCTAssertEqual(mockKeySimulation.keyEvents[5].keyCode, 35)
    }

    func testFinishStreamingInsertionAppendsTrailingSpaceWhenRequested() async throws {
        outputManager.setOutputMode(.directInsert)
        outputManager.beginStreamingInsertion()

        try await outputManager.updateStreamingInsertion(with: "hello")
        mockKeySimulation.keyEvents.removeAll()

        try await outputManager.finishStreamingInsertion(finalText: "hello", appendTrailingSpace: true)

        XCTAssertEqual(mockKeySimulation.keyEvents.count, 2)
        XCTAssertEqual(mockKeySimulation.keyEvents[0].keyCode, 49)
        XCTAssertEqual(mockKeySimulation.keyEvents[1].keyCode, 49)
    }

    func testCancelStreamingInsertionPreservesTypedTextWhenRequested() async throws {
        outputManager.setOutputMode(.directInsert)
        outputManager.beginStreamingInsertion()

        try await outputManager.updateStreamingInsertion(with: "keep me")
        let eventCountBeforeCancel = mockKeySimulation.keyEvents.count

        await outputManager.cancelStreamingInsertion(removeInsertedText: false)

        XCTAssertEqual(mockKeySimulation.keyEvents.count, eventCountBeforeCancel)

        do {
            try await outputManager.updateStreamingInsertion(with: "new text")
            XCTFail("Expected streaming insertion to be inactive after cancel")
        } catch OutputManagerError.textInsertionFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testOutputWithEmptyTextThrowsError() async {
        outputManager.setOutputMode(.clipboard)
        
        do {
            try await outputManager.output("")
            XCTFail("Expected error for empty text")
        } catch OutputManagerError.emptyText {
            XCTAssertNil(mockClipboard.copiedText)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCheckAccessibilityPermission() {
        let hasPermission = outputManager.checkAccessibilityPermission()
        XCTAssertNotNil(hasPermission)
    }
    
    func testDirectInsertRestoresClipboard() async throws {
        outputManager.setOutputMode(.directInsert)
        let testText = "Direct insert test"
        let previousContent = "Previous clipboard content"
        
        mockClipboard.clipboardContent = previousContent
        
        try await outputManager.output(testText)
        
        XCTAssertEqual(mockClipboard.copiedText, previousContent)
        XCTAssertEqual(mockClipboard.clipboardContent, previousContent)
        XCTAssertTrue(mockKeySimulation.pasteSimulated)
        XCTAssertEqual(mockClipboard.clearCount, 2)
    }
    
    func testClipboardModeDoesNotRestoreClipboard() async throws {
        outputManager.setOutputMode(.clipboard)
        let testText = "Clipboard test"
        let previousContent = "Previous content"
        
        mockClipboard.clipboardContent = previousContent
        
        try await outputManager.output(testText)
        
        XCTAssertEqual(mockClipboard.copiedText, testText)
        XCTAssertEqual(mockClipboard.clipboardContent, testText)
        XCTAssertFalse(mockKeySimulation.pasteSimulated)
        XCTAssertEqual(mockClipboard.clearCount, 0)
    }
    
    func testGetKeyCodeForBasicCharacters() {
        let aKeyCode = outputManager.getKeyCodeForCharacter("a")
        XCTAssertNotNil(aKeyCode)
        XCTAssertEqual(aKeyCode?.0, 0)
        XCTAssertTrue(aKeyCode?.1.isEmpty ?? false)
        
        let AKeyCode = outputManager.getKeyCodeForCharacter("A")
        XCTAssertNotNil(AKeyCode)
        XCTAssertEqual(AKeyCode?.0, 0)
        XCTAssertTrue(AKeyCode?.1.contains(.maskShift) ?? false)
        
        let oneKeyCode = outputManager.getKeyCodeForCharacter("1")
        XCTAssertNotNil(oneKeyCode)
        XCTAssertEqual(oneKeyCode?.0, 18)
        
        let spaceKeyCode = outputManager.getKeyCodeForCharacter(" ")
        XCTAssertNotNil(spaceKeyCode)
        XCTAssertEqual(spaceKeyCode?.0, 49)
    }
    
    func testGetKeyCodeForSpecialCharacters() {
        let periodKeyCode = outputManager.getKeyCodeForCharacter(".")
        XCTAssertNotNil(periodKeyCode)
        
        let commaKeyCode = outputManager.getKeyCodeForCharacter(",")
        XCTAssertNotNil(commaKeyCode)
        
        let exclamationKeyCode = outputManager.getKeyCodeForCharacter("!")
        XCTAssertNotNil(exclamationKeyCode)
        XCTAssertTrue(exclamationKeyCode?.1.contains(.maskShift) ?? false)
    }
    
    func testGetKeyCodeForUnsupportedCharacter() {
        let emojiKeyCode = outputManager.getKeyCodeForCharacter("😀")
        XCTAssertNil(emojiKeyCode)
    }
    
    func testErrorDescriptions() {
        XCTAssertNotNil(OutputManagerError.accessibilityPermissionDenied.errorDescription)
        XCTAssertNotNil(OutputManagerError.emptyText.errorDescription)
        XCTAssertNotNil(OutputManagerError.clipboardWriteFailed.errorDescription)
        XCTAssertNotNil(OutputManagerError.textInsertionFailed.errorDescription)
    }
    
    func testMockClipboardTracksOperations() {
        XCTAssertNil(mockClipboard.copiedText)
        XCTAssertNil(mockClipboard.clipboardContent)
        XCTAssertEqual(mockClipboard.clearCount, 0)
        
        let success = mockClipboard.copyToClipboard("test")
        XCTAssertTrue(success)
        XCTAssertEqual(mockClipboard.copiedText, "test")
        XCTAssertEqual(mockClipboard.clipboardContent, "test")
        
        mockClipboard.clearClipboard()
        XCTAssertEqual(mockClipboard.clearCount, 1)
        XCTAssertNil(mockClipboard.clipboardContent)
    }
    
    func testMockKeySimulationTracksEvents() async throws {
        XCTAssertEqual(mockKeySimulation.keyEvents.count, 0)
        XCTAssertFalse(mockKeySimulation.pasteSimulated)
        
        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: true)
        try mockKeySimulation.postKeyEvent(keyCode: 0, flags: [], keyDown: false)
        
        XCTAssertEqual(mockKeySimulation.keyEvents.count, 2)
        XCTAssertTrue(mockKeySimulation.keyEvents[0].keyDown)
        XCTAssertFalse(mockKeySimulation.keyEvents[1].keyDown)
        
        try await mockKeySimulation.simulatePaste()
        XCTAssertTrue(mockKeySimulation.pasteSimulated)
    }
}
