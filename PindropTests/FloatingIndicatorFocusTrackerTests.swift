//
//  FloatingIndicatorFocusTrackerTests.swift
//  PindropTests
//
//  Created on 2026-04-06.
//

import AppKit
import ApplicationServices
import Foundation
import Testing

@testable import Pindrop

@MainActor
private final class MockFloatingIndicatorAXObservationSession: FloatingIndicatorAXObservationSession {
    private let handler: @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    private(set) var invalidateCallCount = 0

    init(handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void) {
        self.handler = handler
    }

    func emit(_ event: FloatingIndicatorAXObservationEvent) {
        handler(event)
    }

    func invalidate() {
        invalidateCallCount += 1
    }
}

@MainActor
private final class MockFloatingIndicatorAXObserver: FloatingIndicatorAXObserving {
    private(set) var beginObservationCallCount = 0
    private(set) var lastSession: MockFloatingIndicatorAXObservationSession?

    func beginObservation(
        handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    ) -> (any FloatingIndicatorAXObservationSession)? {
        beginObservationCallCount += 1
        let session = MockFloatingIndicatorAXObservationSession(handler: handler)
        lastSession = session
        return session
    }
}

@MainActor
private final class MockFloatingIndicatorMousePollingSession: FloatingIndicatorMousePollingSession {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}

@MainActor
private final class FloatingIndicatorTrackerTestClock {
    var current = Date(timeIntervalSinceReferenceDate: 10_000)

    func now() -> Date {
        current
    }

    func advance(by interval: TimeInterval = 1) {
        current = current.addingTimeInterval(interval)
    }
}

@MainActor
private final class MutableMouseDisplayState {
    var displayNumber: UInt32

    init(displayNumber: UInt32) {
        self.displayNumber = displayNumber
    }
}

@MainActor
private final class MockRectDisplayResolver {
    private var displayNumbersByRectKey: [String: UInt32] = [:]

    func setDisplayNumber(_ displayNumber: UInt32, for rect: CGRect) {
        displayNumbersByRectKey[key(for: rect)] = displayNumber
    }

    func displayNumber(for rect: CGRect) -> UInt32? {
        displayNumbersByRectKey[key(for: rect)]
    }

    private func key(for rect: CGRect) -> String {
        let standardized = rect.standardized
        return [
            standardized.origin.x,
            standardized.origin.y,
            standardized.size.width,
            standardized.size.height
        ]
        .map { String(format: "%.3f", $0) }
        .joined(separator: ",")
    }
}

@MainActor
@Suite(.serialized)
struct FloatingIndicatorFocusTrackerTests {
    private struct Fixture {
        let tracker: FloatingIndicatorFocusTracker
        let contextEngineService: ContextEngineService
        let axProvider: MockAXProvider
        let fakeAppElement: AXUIElement
        let fakeFocusedWindow: AXUIElement
        let fakeFocusedElement: AXUIElement
        let axObserver: MockFloatingIndicatorAXObserver
        let mousePollingSession: MockFloatingIndicatorMousePollingSession
        let workspaceNotificationCenter: NotificationCenter
        let clock: FloatingIndicatorTrackerTestClock
        let rectDisplayResolver: MockRectDisplayResolver
        let mouseDisplayState: MutableMouseDisplayState
    }

    private func makeFixture(mouseDisplayNumber: UInt32 = 1) -> Fixture {
        let axProvider = MockAXProvider()
        let fakeAppElement = AXUIElementCreateApplication(77770)
        let fakeFocusedWindow = AXUIElementCreateApplication(77771)
        let fakeFocusedElement = AXUIElementCreateApplication(77772)
        let axObserver = MockFloatingIndicatorAXObserver()
        let mousePollingSession = MockFloatingIndicatorMousePollingSession()
        let workspaceNotificationCenter = NotificationCenter()
        let clock = FloatingIndicatorTrackerTestClock()
        let rectDisplayResolver = MockRectDisplayResolver()
        let mouseDisplayState = MutableMouseDisplayState(displayNumber: mouseDisplayNumber)

        axProvider.isTrusted = true
        axProvider.frontmostPID = 77770
        axProvider.frontmostAppElement = fakeAppElement

        let contextEngineService = ContextEngineService(axProvider: axProvider)
        let tracker = FloatingIndicatorFocusTracker(
            contextEngineService: contextEngineService,
            axProvider: axProvider,
            workspaceNotificationCenter: workspaceNotificationCenter,
            now: clock.now,
            axObservationService: axObserver,
            mouseDisplayNumberProvider: { mouseDisplayState.displayNumber },
            displayNumberForRect: rectDisplayResolver.displayNumber(for:),
            screenResolver: { _ in nil },
            mousePollingScheduler: { _ in
                mousePollingSession
            }
        )

        return Fixture(
            tracker: tracker,
            contextEngineService: contextEngineService,
            axProvider: axProvider,
            fakeAppElement: fakeAppElement,
            fakeFocusedWindow: fakeFocusedWindow,
            fakeFocusedElement: fakeFocusedElement,
            axObserver: axObserver,
            mousePollingSession: mousePollingSession,
            workspaceNotificationCenter: workspaceNotificationCenter,
            clock: clock,
            rectDisplayResolver: rectDisplayResolver,
            mouseDisplayState: mouseDisplayState
        )
    }

    @Test func idlePillSeedsFromCursorDisplay() throws {
        let fixture = makeFixture(mouseDisplayNumber: 12)

        fixture.tracker.start(mode: .idlePill)
        defer { fixture.tracker.stop() }

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement.displayNumber == 12)
        #expect(placement.source == .mouse)
    }

    @Test func activeSessionSeedsFromFocusedWindowDisplayWhenAvailable() throws {
        let fixture = makeFixture(mouseDisplayNumber: 2)
        let windowRect = CGRect(x: 400, y: 200, width: 800, height: 600)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(7, for: windowRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement.displayNumber == 7)
        #expect(placement.source == .focusedWindow)
    }

    @Test func activeSessionFallsBackToFocusedElementDisplayWhenWindowGeometryUnavailable() throws {
        let fixture = makeFixture(mouseDisplayNumber: 2)
        let anchorRect = CGRect(x: 1600, y: 900, width: 8, height: 24)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setElementAttribute(kAXFocusedUIElementAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedElement)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedElement, value: anchorRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedElement, value: anchorRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(9, for: anchorRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement.displayNumber == 9)
        #expect(placement.source == .focusedElement)
    }

    @Test func activeSessionPreservesExistingPlacementWhenFocusCannotBeResolved() throws {
        let fixture = makeFixture(mouseDisplayNumber: 4)

        fixture.tracker.start(mode: .idlePill)
        let idlePlacement = try #require(fixture.tracker.placementContext)
        fixture.tracker.start(mode: .activeSession)

        let activePlacement = try #require(fixture.tracker.placementContext)
        #expect(activePlacement == idlePlacement)
    }

    @Test func modeTransitionToActiveSessionReseedsFromFocusedWindowPlacement() throws {
        let fixture = makeFixture(mouseDisplayNumber: 4)
        let windowRect = CGRect(x: 1600, y: 120, width: 900, height: 700)

        fixture.tracker.start(mode: .idlePill)
        let idlePlacement = try #require(fixture.tracker.placementContext)
        #expect(idlePlacement.displayNumber == 4)
        #expect(idlePlacement.source == .mouse)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(7, for: windowRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let activePlacement = try #require(fixture.tracker.placementContext)
        #expect(activePlacement.displayNumber == 7)
        #expect(activePlacement.source == .focusedWindow)
    }

    @Test func modeTransitionToIdlePillReseedsFromMousePlacement() throws {
        let fixture = makeFixture(mouseDisplayNumber: 4)
        let windowRect = CGRect(x: 1600, y: 120, width: 900, height: 700)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(7, for: windowRect)

        fixture.tracker.start(mode: .activeSession)

        let activePlacement = try #require(fixture.tracker.placementContext)
        #expect(activePlacement.displayNumber == 7)
        #expect(activePlacement.source == .focusedWindow)

        fixture.tracker.start(mode: .idlePill)
        defer { fixture.tracker.stop() }

        let idlePlacement = try #require(fixture.tracker.placementContext)
        #expect(idlePlacement.displayNumber == 4)
        #expect(idlePlacement.source == .mouse)
    }

    @Test func activeSessionIgnoresMouseDisplayChangesAfterFocusPlacement() throws {
        let fixture = makeFixture(mouseDisplayNumber: 1)
        let windowRect = CGRect(x: 50, y: 50, width: 640, height: 480)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(3, for: windowRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let initialPlacement = try #require(fixture.tracker.placementContext)
        #expect(initialPlacement.displayNumber == 3)
        #expect(initialPlacement.source == .focusedWindow)

        fixture.mouseDisplayState.displayNumber = 8
        fixture.clock.advance()
        fixture.tracker.handleMouseTick()

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement == initialPlacement)
    }

    @Test func focusedWindowChangeOverridesOlderMousePlacement() throws {
        let fixture = makeFixture(mouseDisplayNumber: 2)
        let windowRect = CGRect(x: 1200, y: 120, width: 900, height: 700)

        fixture.tracker.start(mode: .idlePill)
        defer { fixture.tracker.stop() }

        fixture.mouseDisplayState.displayNumber = 5
        fixture.clock.advance()
        fixture.tracker.handleMouseTick()

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(11, for: windowRect)

        fixture.clock.advance()
        fixture.axObserver.lastSession?.emit(.focusedWindowChanged)

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement.displayNumber == 11)
        #expect(placement.source == .focusedWindow)
    }

    @Test func frontmostAppActivationReinstallsObserversAndUpdatesPlacement() async throws {
        let fixture = makeFixture(mouseDisplayNumber: 1)
        let initialWindowRect = CGRect(x: 20, y: 20, width: 500, height: 400)
        let activatedWindowRect = CGRect(x: 1600, y: 40, width: 500, height: 400)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: initialWindowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: initialWindowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(2, for: initialWindowRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: activatedWindowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: activatedWindowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(14, for: activatedWindowRect)

        fixture.clock.advance()
        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await Task.yield()

        let placement = try #require(fixture.tracker.placementContext)
        #expect(fixture.axObserver.beginObservationCallCount == 2)
        #expect(placement.displayNumber == 14)
        #expect(placement.source == .frontmostApplication)
    }

    @Test func unresolvedAXEventsDoNotClobberExistingPlacement() throws {
        let fixture = makeFixture(mouseDisplayNumber: 3)
        let windowRect = CGRect(x: 90, y: 90, width: 500, height: 400)

        fixture.axProvider.setElementAttribute(kAXFocusedWindowAttribute, of: fixture.fakeAppElement, value: fixture.fakeFocusedWindow)
        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: windowRect.origin)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: windowRect.size)
        fixture.rectDisplayResolver.setDisplayNumber(6, for: windowRect)

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let initialPlacement = try #require(fixture.tracker.placementContext)

        fixture.axProvider.setPointAttribute(kAXPositionAttribute, of: fixture.fakeFocusedWindow, value: .zero)
        fixture.axProvider.setSizeAttribute(kAXSizeAttribute, of: fixture.fakeFocusedWindow, value: .zero)

        fixture.clock.advance()
        fixture.axObserver.lastSession?.emit(.focusedWindowChanged)

        #expect(fixture.tracker.placementContext == initialPlacement)
    }

    @Test func activeSessionFallsBackToMousePlacementWhenAXIsUnavailable() throws {
        let fixture = makeFixture(mouseDisplayNumber: 15)
        fixture.axProvider.isTrusted = false

        fixture.tracker.start(mode: .activeSession)
        defer { fixture.tracker.stop() }

        let placement = try #require(fixture.tracker.placementContext)
        #expect(placement.displayNumber == 15)
        #expect(placement.source == .mouse)
    }
}
