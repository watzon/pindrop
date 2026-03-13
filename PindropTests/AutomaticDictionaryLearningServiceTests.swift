//
//  AutomaticDictionaryLearningServiceTests.swift
//  PindropTests
//
//  Created on 2026-03-11.
//

import XCTest
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
final class AutomaticDictionaryLearningServiceTests: XCTestCase {
    private var snapshotProvider: MockFocusedTextSnapshotProvider!
    private var changeObserver: MockFocusedTextChangeObserver!
    private var store: MockLearnedReplacementStore!
    private var toastService: MockToastService!
    private var service: AutomaticDictionaryLearningService!

    override func setUp() async throws {
        snapshotProvider = MockFocusedTextSnapshotProvider()
        changeObserver = MockFocusedTextChangeObserver()
        store = MockLearnedReplacementStore()
        toastService = MockToastService()
        service = AutomaticDictionaryLearningService(
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
    }

    override func tearDown() async throws {
        service = nil
        toastService = nil
        store = nil
        changeObserver = nil
        snapshotProvider = nil
    }

    func testDetectorFindsSimpleOneWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh ",
            observedSnapshot: makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        )

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }

    func testDetectorSupportsCasingChanges() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "iphone",
            observedSnapshot: makeSnapshot(text: "iPhone", selectedRange: CFRange(location: 6, length: 0))
        )

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "iphone", replacement: "iPhone"))
    }

    func testDetectorSupportsPunctuationAdjacentCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh,",
            observedSnapshot: makeSnapshot(text: "the,", selectedRange: CFRange(location: 4, length: 0))
        )

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }

    func testDetectorSupportsMergedSplitWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "a UR ",
            observedSnapshot: makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0))
        )

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "a UR", replacement: "AUR"))
    }

    func testDetectorSupportsThreeTokenMergedWordCorrection() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "chat g p t ",
            observedSnapshot: makeSnapshot(text: "ChatGPT ", selectedRange: CFRange(location: 8, length: 0))
        )

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "chat g p t", replacement: "ChatGPT"))
    }

    func testDetectorSupportsCorrectionWhenOtherFieldChangesExistOutsideInsertedSegment() {
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

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "teh", replacement: "the"))
    }

    func testDetectorSupportsCorrectionWhenObservedAXTextOnlyContainsInsertedBlock() {
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

        XCTAssertEqual(candidate, LearnedCorrectionCandidate(original: "Quen", replacement: "Qwen"))
    }

    func testDetectorIgnoresAmbiguousRepeatedTokenCases() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh teh",
            observedSnapshot: makeSnapshot(text: "the teh", selectedRange: CFRange(location: 7, length: 0))
        )

        XCTAssertNil(candidate)
    }

    func testDetectorIgnoresMultiWordEdits() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh foo",
            observedSnapshot: makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0))
        )

        XCTAssertNil(candidate)
    }

    func testDetectorIgnoresMergedReplacementWhenWordsDoNotCollapseToReplacement() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "new york ",
            observedSnapshot: makeSnapshot(text: "NYC ", selectedRange: CFRange(location: 3, length: 0))
        )

        XCTAssertNil(candidate)
    }

    func testDetectorIgnoresDeletionOrAppendOnlyEdits() {
        let candidate = AutomaticDictionaryLearningDetector.detectCorrection(
            preInsertSnapshot: makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0)),
            insertedText: "teh",
            observedSnapshot: makeSnapshot(text: "teh extra", selectedRange: CFRange(location: 9, length: 0))
        )

        XCTAssertNil(candidate)
    }

    func testStableCorrectionPersistsExactlyOnce() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.upsertCalls.count, 1)
        XCTAssertEqual(store.upsertCalls.first?.original, "teh")
        XCTAssertEqual(store.upsertCalls.first?.replacement, "the")
    }

    func testTimeoutOrContextSwitchDoesNotPersistCorrection() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            FocusedTextSnapshot(
                appBundleIdentifier: "com.apple.TextEdit",
                windowTitle: "Different",
                focusedElementRole: "AXTextArea",
                text: "the ",
                selectedRange: CFRange(location: 4, length: 0),
                anchorRect: nil
            )
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(store.upsertCalls.isEmpty)
        XCTAssertTrue(toastService.shownPayloads.isEmpty)
    }

    func testSuccessfulLearnShowsUndoToastAndUndoRollsBackChange() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0), anchorRect: CGRect(x: 10, y: 10, width: 20, height: 20))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(toastService.shownPayloads.count, 1)
        XCTAssertEqual(toastService.shownPayloads.first?.message, "Added 'the' to dictionary")
        XCTAssertEqual(toastService.shownPayloads.first?.actions.count, 1)

        toastService.shownPayloads.first?.actions.first?.handler()

        XCTAssertEqual(store.undoCalls.count, 1)
        XCTAssertEqual(store.undoCalls.first?.learnedOriginal, "teh")
    }

    func testFallbackPollingLearnsWhenChangeNotificationsAreUnavailable() async throws {
        changeObserver.supportsChangeNotifications = false

        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(store.upsertCalls.count, 1)
        XCTAssertGreaterThanOrEqual(snapshotProvider.captureCallCount, 2)
    }

    func testSessionCanLearnMultipleCorrectionsWithinSameObservation() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "the foo", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the foo", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0)),
            makeSnapshot(text: "the bar", selectedRange: CFRange(location: 7, length: 0))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh foo")

        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(store.upsertCalls.count, 2)
        XCTAssertEqual(store.upsertCalls[0].original, "teh")
        XCTAssertEqual(store.upsertCalls[0].replacement, "the")
        XCTAssertEqual(store.upsertCalls[1].original, "foo")
        XCTAssertEqual(store.upsertCalls[1].replacement, "bar")
    }

    func testSpuriousFrontmostAppActivationDoesNotStopLearningIfSnapshotStillMatches() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0)),
            makeSnapshot(text: "the ", selectedRange: CFRange(location: 4, length: 0))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "teh ")
        changeObserver.lastSession?.emit(
            .frontmostApplicationChanged(
                bundleIdentifier: "tech.watzon.pindrop",
                localizedName: "Pindrop",
                processIdentifier: 999
            )
        )
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.upsertCalls.count, 1)
        XCTAssertEqual(store.upsertCalls.first?.original, "teh")
        XCTAssertEqual(store.upsertCalls.first?.replacement, "the")
    }

    func testMergedSplitWordCorrectionPersistsExactlyOnce() async throws {
        let preInsert = makeSnapshot(text: "", selectedRange: CFRange(location: 0, length: 0))
        snapshotProvider.snapshots = [
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0)),
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0)),
            makeSnapshot(text: "AUR ", selectedRange: CFRange(location: 3, length: 0))
        ]

        service.beginObservation(preInsertSnapshot: preInsert, insertedText: "a UR ")
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))
        changeObserver.lastSession?.emit(.textMayHaveChanged(source: "test"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.upsertCalls.count, 1)
        XCTAssertEqual(store.upsertCalls.first?.original, "a UR")
        XCTAssertEqual(store.upsertCalls.first?.replacement, "AUR")
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
