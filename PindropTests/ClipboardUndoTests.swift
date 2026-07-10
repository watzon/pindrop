//
//  ClipboardUndoTests.swift
//  PindropTests
//
//  Created on 2026-07-09.
//

import AppKit
import Foundation
import Testing
@testable import Pindrop

@MainActor
@Suite
struct ClipboardUndoTests {
    @Test func copyReplacingClipboardSnapshotsAndWritesNewText() throws {
        let mockClipboard = MockClipboard()
        mockClipboard.clipboardContent = "prior contents"
        mockClipboard.changeCount = 3

        let outputManager = OutputManager(
            outputMode: .clipboard,
            clipboard: mockClipboard,
            keySimulation: MockKeySimulation()
        )

        let snapshot = try outputManager.copyReplacingClipboard("new transcript")

        #expect(mockClipboard.copiedText == "new transcript")
        #expect(mockClipboard.clipboardContent == "new transcript")
        #expect(snapshot.changeCount == 3)
        #expect(!snapshot.items.isEmpty)
    }

    @Test func restoreClipboardSnapshotRoundTripsPriorString() throws {
        let mockClipboard = MockClipboard()
        mockClipboard.clipboardContent = "original pasteboard"
        mockClipboard.changeCount = 1

        let outputManager = OutputManager(
            outputMode: .clipboard,
            clipboard: mockClipboard,
            keySimulation: MockKeySimulation()
        )

        let snapshot = try outputManager.copyReplacingClipboard("replacement text")
        #expect(mockClipboard.clipboardContent == "replacement text")

        let restored = outputManager.restoreClipboardSnapshot(snapshot)
        #expect(restored)
        #expect(mockClipboard.restoreCount == 1)
        #expect(mockClipboard.clipboardContent == "original pasteboard")
    }

    @Test func emptyPriorClipboardRestoresToEmpty() throws {
        let mockClipboard = MockClipboard()
        // No prior content
        let outputManager = OutputManager(
            outputMode: .clipboard,
            clipboard: mockClipboard,
            keySimulation: MockKeySimulation()
        )

        let snapshot = try outputManager.copyReplacingClipboard("only content")
        #expect(mockClipboard.clipboardContent == "only content")

        #expect(outputManager.restoreClipboardSnapshot(snapshot))
        #expect(mockClipboard.clipboardContent == nil)
    }

    @Test func captureAndRestoreThroughPublicSeams() throws {
        let mockClipboard = MockClipboard()
        mockClipboard.clipboardContent = "alpha"
        let outputManager = OutputManager(
            outputMode: .clipboard,
            clipboard: mockClipboard,
            keySimulation: MockKeySimulation()
        )

        let snapshot = outputManager.captureClipboardSnapshot()
        try outputManager.copyToClipboard("beta")
        #expect(mockClipboard.clipboardContent == "beta")
        #expect(outputManager.restoreClipboardSnapshot(snapshot))
        #expect(mockClipboard.clipboardContent == "alpha")
    }
}
