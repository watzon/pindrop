//
//  AutomaticDictionaryLearningServiceTests.swift
//  PindropTests
//
//  Created on 2026-03-11.
//

import CoreFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class MockFocusedTextSnapshotProvider: FocusedTextSnapshotCapturing {
    var snapshots: [FocusedTextSnapshot?] = []
    private(set) var captureCallCount = 0

    func captureFocusedTextSnapshot() -> FocusedTextSnapshot? {
        captureCallCount += 1
        if snapshots.isEmpty {
            return nil
        }

        let next = snapshots.removeFirst()
        if snapshots.isEmpty {
            snapshots = [next]
        }
        return next
    }
}

@MainActor
private final class MockLearnedReplacementStore: LearnedReplacementPersisting {
    var nextChange: LearnedReplacementChange? = LearnedReplacementChange(
        replacementID: UUID(),
        replacement: "the",
        learnedOriginal: "teh",
        createdReplacement: true
    )
    private(set) var upsertCalls: [(original: String, replacement: String)] = []
    private(set) var undoCalls: [LearnedReplacementChange] = []

    func upsertLearnedReplacement(original: String, replacement: String) throws -> LearnedReplacementChange? {
        upsertCalls.append((original, replacement))
        return nextChange
    }

    func undoLearnedReplacement(_ change: LearnedReplacementChange) throws {
        undoCalls.append(change)
    }
}

@MainActor
private final class MockToastService: ToastShowing {
    private(set) var shownPayloads: [ToastPayload] = []

    func show(_ payload: ToastPayload) {
        shownPayloads.append(payload)
    }
}

@MainActor
private final class MockFocusedTextObservationSession: FocusedTextObservationSession {
    let supportsChangeNotifications: Bool
    private let handler: @MainActor (FocusedTextObservationEvent) -> Void
    private(set) var invalidateCallCount = 0

    init(
        supportsChangeNotifications: Bool,
        handler: @escaping @MainActor (FocusedTextObservationEvent) -> Void
    ) {
        self.supportsChangeNotifications = supportsChangeNotifications
        self.handler = handler
    }

    func emit(_ event: FocusedTextObservationEvent) {
        handler(event)
    }

    func invalidate() {
        invalidateCallCount += 1
    }
}

@MainActor
private final class MockFocusedTextChangeObserver: FocusedTextChangeObserving {
    var supportsChangeNotifications = true
    var returnsSession = true
    private(set) var beginObservationCallCount = 0
    private(set) var lastSession: MockFocusedTextObservationSession?

    func beginObservation(
        handler: @escaping @MainActor (FocusedTextObservationEvent) -> Void
    ) -> (any FocusedTextObservationSession)? {
        beginObservationCallCount += 1
        guard returnsSession else {
            lastSession = nil
            return nil
        }

        let session = MockFocusedTextObservationSession(
            supportsChangeNotifications: supportsChangeNotifications,
            handler: handler
        )
        lastSession = session
        return session
    }
}

@MainActor
@Suite(.serialized)
struct AutomaticDictionaryLearningServiceTests {
    private struct Fixture {
        let snapshotProvider: MockFocusedTextSnapshotProvider
        let changeObserver: MockFocusedTextChangeObserver
        let store: MockLearnedReplacementStore
        let toastService: MockToastService
        let service: AutomaticDictionaryLearningService
    }

    private func makeFixture() -> Fixture {
        let snapshotProvider = MockFocusedTextSnapshotProvider()
        let changeObserver = MockFocusedTextChangeObserver()
        let store = MockLearnedReplacementStore()
        let toastService = MockToastService()
        let service = AutomaticDictionaryLearningService(
            snapshotProvider: snapshotProvider,
            changeObserver: changeObserver,
            dictionaryStore: store,
            toastService: toastService,
            configuration: AutomaticDictionaryLearningConfiguration(
                pollInterval: .milliseconds(10),
                stabilityWindow: .milliseconds(20),
                observationTimeout: .milliseconds(120)
            )
        )

        return Fixture(
            snapshotProvider: snapshotProvider,
            changeObserver: changeObserver,
            store: store,
            toastService: toastService,
            service: service
        )
    }

    @Test func testDetectorFindsSimpleOneWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh ",
            observedSnapshot: makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }
    @Test func testDetectorSupportsCasingChanges() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "iphone",
            observedSnapshot: makeSnapshot(text: "iPhone", selectedRange: CFRange(location: 6, length: 0))
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "iphone", replacement: "iPhone"))
    }
    @Test func testDetectorSupportsPunctuationAdjacentCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh,",
            observedSnapshot: makeSnapshot(text: "the,", selectedRange: CFRange(location: 4, length: 0))
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }
    @Test func testDetectorSupportsMergedSplitWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "a UR ",
            observedSnapshot: makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0))
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "a UR", replacement: "AUR"))
    }
    @Test func testDetectorSupportsThreeTokenMergedWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "chat g p t ",
            observedSnapshot: makeSnapshot(text: "ChatGPT ", selectedRange: CFRange(location: 8, length: 0))
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "chat g p t", replacement: "ChatGPT"))
    }
    @Test func testDetectorSupportsCorrectionWhenOtherFieldChangesExistOutsideInsertedSegment() {
        let originalText = "Outside changes can happen earlier in the field while anchor text remains stable. "
        let selectedRange = CFRange(location: (originalText as NSString).length, length: 0)
        let observedText = "outside changes can happen earlier in the field while anchor text remains stable. the "

        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: originalText, selectedRange: selectedRange),
            insertedText: "teh ",
            observedSnapshot: makeSnapshot(
                text: observedText,
                selectedRange: CFRange(location: (observedText as NSString).length, length: 0)
            )
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }
    @Test func testDetectorSupportsCorrectionWhenObservedAXTextOnlyContainsInsertedBlock() {
        let originalText = "\nAsk for follow-up changes if needed."
        let insertedText = "Quen is easily one of the best models out there right now. "
        let observedText = "Qwen is easily one of the best models out there right now. "

        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: originalText, selectedRange: CFRange(location: 0, length: 0)),
            insertedText: insertedText,
            observedSnapshot: makeSnapshot(
                text: observedText,
                selectedRange: CFRange(location: 4, length: 0)
            )
        )

        #expect(candidate == LearnedCorrectionCandidate(original: "Quen", replacement: "Qwen"))
    }
    @Test func testDetectorIgnoresAmbiguousRepeatedTokenCases() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh teh",
            observedSnapshot: makeSnapshot(text: "the teh", selectedRange: CFRange(location: 7, length: 0))
        )

        #expect(candidate == nil)
    }
    @Test func testDetectorIgnoresMultiWordEdits() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh foo",
            observedSnapshot: makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0))
        )

        #expect(candidate == nil)
    }
    @Test func testDetectorIgnoresMergedReplacementWhenWordsDoNotCollapseToReplacement() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "new york ",
            observedSnapshot: makeSnapshot(text: "NYC ", selectedRange: CFRange(location: 3, length: 0))
        )

        #expect(candidate == nil)
    }
    @Test func testDetectorIgnoresDeletionOrAppendOnlyEdits() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh",
            observedSnapshot: makeSnapshot(text: "teh extra", selectedRange: CFRange(location: 9, length: 0))
        )

        #expect(candidate == nil)
    }
    @Test func testStableCorrectionPersistsExactlyOnce() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        #expect(fixture.store.upsertCalls.count == 1)
        #expect(fixture.store.upsertCalls.first?.original == "teh")
        #expect(fixture.store.upsertCalls.first?.replacement == "the")
    }
    @Test func testTimeoutOrContextSwitchDoesNotPersistCorrection() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            FocusedTextSnapshot(
                appBundleIdentifier: "com.apple.TextEdit",
                windowTitle: "Different",
                focusedElementRole: "AXTextArea",
                text: "the ",
                selectedRange: CFRange(location: 4, length: 0),
                anchorRect: nil
            )
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(20))

        #expect(fixture.store.upsertCalls.isEmpty)
        #expect(fixture.toastService.shownPayloads.isEmpty)
    }
    @Test func testSuccessfulLearnShowsUndoToastAndUndoRollsBackChange() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        #expect(fixture.toastService.shownPayloads.count == 1)
        #expect(fixture.toastService.shownPayloads.first?.message == "Added 'the' to dictionary")
        #expect(fixture.toastService.shownPayloads.first?.actions.count == 1)

        fixture.toastService.shownPayloads.first?.actions.first?.handler()

        #expect(fixture.store.undoCalls.count == 1)
        #expect(fixture.store.undoCalls.first?.learnedOriginal == "teh")
    }
    @Test func testFallbackPollingLearnsWhenChangeNotificationsAreUnavailable() async throws {
        let fixture = makeFixture()
        fixture.changeObserver.supportsChangeNotifications = false

        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        try await Task.sleep(for: .milliseconds(140))

        #expect(fixture.store.upsertCalls.count == 1)
        #expect(fixture.snapshotProvider.captureCallCount >= 2)
    }
    @Test func testSessionCanLearnMultipleCorrectionsWithinSameObservation() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "the foo", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the foo", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh foo")

        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))

        #expect(fixture.store.upsertCalls.count == 2)
        let firstCall = try #require(fixture.store.upsertCalls.first)
        let secondCall = try #require(fixture.store.upsertCalls.dropFirst().first)
        #expect(firstCall.original == "teh")
        #expect(firstCall.replacement == "the")
        #expect(secondCall.original == "foo")
        #expect(secondCall.replacement == "bar")
    }
    @Test func testSpuriousFrontmostAppActivationDoesNotStopLearningIfSnapshotStillMatches() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        fixture.changeObserver.lastSession?.emit(
            .frontmostApplicationChanged(
                bundleIdentifier: "tech.watzon.pindrop",
                localizedName: "Pindrop",
                processIdentifier: 999
            )
        )
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        #expect(fixture.store.upsertCalls.count == 1)
        #expect(fixture.store.upsertCalls.first?.original == "teh")
        #expect(fixture.store.upsertCalls.first?.replacement == "the")
    }
    @Test func testMergedSplitWordCorrectionPersistsExactlyOnce() async throws {
        let fixture = makeFixture()
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        fixture.snapshotProvider.snapshots = [
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0)),
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0)),
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0))
        ]

        fixture.service.beginObservation(preInsertSnapshot: preInsert, insertedText: "a UR ")
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        fixture.changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        #expect(fixture.store.upsertCalls.count == 1)
        #expect(fixture.store.upsertCalls.first?.original == "a UR")
        #expect(fixture.store.upsertCalls.first?.replacement == "AUR")
    }

    private func makeSnapshot(
        text: String,
        selectedRange: CFRange,
        anchorRect: CGRect? = nil
    ) -> FocusedTextSnapshot {
        FocusedTextSnapshot(
            appBundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Test",
            focusedElementRole: "AXTextArea",
            text: text,
            selectedRange: selectedRange,
            anchorRect: anchorRect
        )
    }
}
