//
//  PerformanceRegressionTests.swift
//  PindropTests
//
//  Behavioral regression coverage for completed performance fixes:
//  live-transcript display bounding, media-playback teardown, and other
//  side-effect-free lifecycle contracts reachable without CoreAudio hardware.
//

import AVFoundation
import Foundation
import Testing
@testable import Pindrop

// MARK: - Live transcript display bounds

@MainActor
@Suite("LiveTranscriptState performance")
struct LiveTranscriptStatePerformanceTests {

    @Test func retainsFullDisplayTextWhileBoundingDisplayTail() {
        let state = LiveTranscriptState()
        state.begin()

        // Build a multi-word stream longer than the viewport budget so the
        // display tail must truncate while the authoritative cache stays whole.
        let words = (0..<120).map { "word\($0)" }
        let committed = words.joined(separator: " ")
        #expect(committed.count > LiveTranscriptState.displayTailCharacterLimit)

        state.update(committed: committed, tentative: " trailing")

        let expectedFull = StreamingRefinementCoordinator.composeDisplay(
            committed: committed,
            tentative: " trailing"
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(state.phase == .streaming)
        #expect(state.isActive)
        #expect(state.displayText == expectedFull)
        #expect(state.displayText.count > LiveTranscriptState.displayTailCharacterLimit)
        #expect(state.displayTail.count <= LiveTranscriptState.displayTailCharacterLimit)
        #expect(state.displayText.hasSuffix(state.displayTail))
        #expect(state.displayTail == LiveTranscriptState.makeDisplayTail(from: expectedFull))
    }

    @Test func makeDisplayTailPrefersNearbyWordBoundary() {
        // Last `limit` characters begin mid-token ("ab …"); a short orphaned
        // prefix should be skipped at the first whitespace so the viewport
        // does not open on a sliced word.
        let text = String(repeating: "x", count: 10) + "ab hello there friends"
        let tail = LiveTranscriptState.makeDisplayTail(from: text, limit: 22)

        #expect(tail == "hello there friends")
        #expect(!tail.hasPrefix("ab"))
        #expect(tail.count <= 22)
    }

    @Test func makeDisplayTailReturnsShortTextUnchanged() {
        let short = "hello world"
        #expect(LiveTranscriptState.makeDisplayTail(from: short) == short)
    }

    @Test func endClearsFullAndBoundedDisplayCaches() {
        let state = LiveTranscriptState()
        state.begin()

        let longCommitted = String(repeating: "alpha ", count: 80)
        state.update(committed: longCommitted, tentative: "beta")
        #expect(!state.displayText.isEmpty)
        #expect(!state.displayTail.isEmpty)
        #expect(state.phase == .streaming)

        state.beginEnhancing()
        #expect(state.phase == .enhancing)
        #expect(!state.displayText.isEmpty)

        state.end()

        #expect(state.phase == .inactive)
        #expect(!state.isActive)
        #expect(state.committedText.isEmpty)
        #expect(state.tentativeText.isEmpty)
        #expect(state.displayText.isEmpty)
        #expect(state.displayTail.isEmpty)
    }

    @Test func beginResetsPriorSessionCaches() {
        let state = LiveTranscriptState()
        state.begin()
        state.update(committed: "previous session", tentative: " leftover")
        #expect(!state.displayText.isEmpty)

        state.begin()

        #expect(state.phase == .streaming)
        #expect(state.committedText.isEmpty)
        #expect(state.tentativeText.isEmpty)
        #expect(state.displayText.isEmpty)
        #expect(state.displayTail.isEmpty)
    }

    @Test func identicalUpdatesDoNotChangeDisplayCaches() {
        let state = LiveTranscriptState()
        state.begin()
        state.update(committed: "stable", tentative: " partial")

        let displayBefore = state.displayText
        let tailBefore = state.displayTail

        state.update(committed: "stable", tentative: " partial")

        #expect(state.displayText == displayBefore)
        #expect(state.displayTail == tailBefore)
    }
}

// MARK: - Media playback teardown

@MainActor
@Suite("MediaPlaybackController performance")
struct MediaPlaybackControllerPerformanceTests {

    /// Creates a tiny valid local media file so `AVPlayerItem` construction is
    /// real but never depends on network or CoreAudio hardware.
    private func makeTemporaryMediaURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pindrop-playback-\(UUID().uuidString).m4a")
        // Empty file is enough for load/teardown lifecycle; asset metadata may
        // fail asynchronously, which the controller already guards against.
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        return url
    }

    @Test func teardownWithoutActiveItemIsIdempotentAndResetsObservableState() {
        let controller = MediaPlaybackController()

        // Fresh controller starts torn down — repeated teardown must stay a no-op.
        controller.teardownPlayback()
        controller.teardownPlayback()

        #expect(controller.isPlaying == false)
        #expect(controller.currentTime == 0)
        #expect(controller.duration == 0)
        #expect(controller.hasVideoTrack == false)
        #expect(controller.player.currentItem == nil)
        #expect(controller.player.rate == 0)
    }

    @Test func teardownAfterLoadClearsPlayerItemAndObservableState() throws {
        let controller = MediaPlaybackController()
        let url = try makeTemporaryMediaURL()
        defer { try? FileManager.default.removeItem(at: url) }

        controller.load(url: url)
        #expect(controller.player.currentItem != nil)

        // Seed observable fields the way a live session would, then tear down.
        controller.isPlaying = true
        controller.currentTime = 12.5
        controller.duration = 40
        controller.hasVideoTrack = true

        controller.teardownPlayback()

        #expect(controller.isPlaying == false)
        #expect(controller.currentTime == 0)
        #expect(controller.duration == 0)
        #expect(controller.hasVideoTrack == false)
        #expect(controller.player.currentItem == nil)
        #expect(controller.player.rate == 0)

        // Second teardown must not re-touch already-cleared state.
        controller.currentTime = 3
        controller.teardownPlayback()
        #expect(controller.currentTime == 3)
    }

    @Test func loadAfterTeardownReplacesItemCleanly() throws {
        let controller = MediaPlaybackController()
        let firstURL = try makeTemporaryMediaURL()
        let secondURL = try makeTemporaryMediaURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        controller.load(url: firstURL)
        let firstItem = controller.player.currentItem
        #expect(firstItem != nil)

        controller.teardownPlayback()
        #expect(controller.player.currentItem == nil)

        controller.load(url: secondURL)
        let secondItem = controller.player.currentItem
        #expect(secondItem != nil)
        #expect(secondItem !== firstItem)

        controller.teardownPlayback()
        #expect(controller.player.currentItem == nil)
    }
}
