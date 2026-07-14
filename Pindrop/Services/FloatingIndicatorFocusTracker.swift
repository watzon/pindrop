//
//  FloatingIndicatorFocusTracker.swift
//  Pindrop
//
//  Created on 2026-04-06.
//

import AppKit
import ApplicationServices
import Foundation

enum FloatingIndicatorFocusSource: Equatable {
    case mouse
    case frontmostApplication
    case focusedWindow
    case focusedElement
}

enum FloatingIndicatorTrackingMode: Equatable {
    case idlePill
    case activeSession
}

struct FloatingIndicatorPlacementContext: Equatable {
    let displayNumber: UInt32
    let source: FloatingIndicatorFocusSource
    let updatedAt: Date
}

@MainActor
protocol FloatingIndicatorAXObservationSession: AnyObject {
    func invalidate()
}

@MainActor
protocol FloatingIndicatorMousePollingSession: AnyObject {
    func invalidate()
}

enum FloatingIndicatorAXObservationEvent {
    case focusedWindowChanged
    case focusedElementChanged
}

@MainActor
protocol FloatingIndicatorAXObserving: AnyObject {
    func beginObservation(
        handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    ) -> (any FloatingIndicatorAXObservationSession)?
}

private func floatingIndicatorDefaultMouseDisplayNumber() -> UInt32? {
    let displayNumber = NSScreen.screenUnderMouse().pindrop_displayNumber
    return displayNumber == 0 ? nil : displayNumber
}

@MainActor
private func floatingIndicatorDefaultMousePollingScheduler(
    handler: @escaping @MainActor () -> Void
) -> any FloatingIndicatorMousePollingSession {
    // Event-driven: mouse-move monitors + screen reconfiguration notifications.
    // Replaces the previous 20 Hz timer that allocated a MainActor Task every tick.
    FloatingIndicatorEventDrivenMouseSession(handler: handler)
}

private func floatingIndicatorDefaultScreen(for displayNumber: UInt32) -> NSScreen? {
    NSScreen.screens.first { $0.pindrop_displayNumber == displayNumber }
}

private func floatingIndicatorDefaultDisplayNumber(for rect: CGRect) -> UInt32? {
    let standardizedRect = rect.standardized
    guard !standardizedRect.isNull, !standardizedRect.isEmpty else { return nil }

    let midpoint = CGPoint(x: standardizedRect.midX, y: standardizedRect.midY)
    if let midpointScreen = NSScreen.screens.first(where: {
        $0.frame.contains(midpoint) || $0.visibleFrame.contains(midpoint)
    }) {
        let displayNumber = midpointScreen.pindrop_displayNumber
        return displayNumber == 0 ? nil : displayNumber
    }

    let bestIntersection = NSScreen.screens
        .compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
            let intersection = standardizedRect.intersection(screen.frame)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            return (screen, intersection.width * intersection.height)
        }
        .max { $0.area < $1.area }

    let displayNumber = bestIntersection?.screen.pindrop_displayNumber ?? 0
    return displayNumber == 0 ? nil : displayNumber
}

@MainActor
final class FloatingIndicatorFocusTracker {
    private let contextEngineService: ContextEngineService
    private let workspaceNotificationCenter: NotificationCenter
    private let now: () -> Date
    private let axObservationService: any FloatingIndicatorAXObserving
    private let mouseDisplayNumberProvider: () -> UInt32?
    private let displayNumberForRect: (CGRect) -> UInt32?
    private let screenResolver: (UInt32) -> NSScreen?
    private let mousePollingScheduler: @MainActor (@escaping @MainActor () -> Void) -> any FloatingIndicatorMousePollingSession
    /// Nonisolated resource ownership so `deinit` can remove the workspace
    /// observer without touching MainActor-isolated stored properties.
    private let resources: FloatingIndicatorFocusTrackerResources

    private var trackingMode: FloatingIndicatorTrackingMode?
    private var placementContextValue: FloatingIndicatorPlacementContext?
    private var mousePollingSession: (any FloatingIndicatorMousePollingSession)?
    private var axObservationSession: (any FloatingIndicatorAXObservationSession)?
    private var lastObservedMouseDisplayNumber: UInt32?

    init(
        contextEngineService: ContextEngineService,
        axProvider: AXProviderProtocol = SystemAXProvider(),
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init,
        axObservationService: (any FloatingIndicatorAXObserving)? = nil,
        mouseDisplayNumberProvider: @escaping () -> UInt32? = floatingIndicatorDefaultMouseDisplayNumber,
        displayNumberForRect: @escaping (CGRect) -> UInt32? = floatingIndicatorDefaultDisplayNumber(for:),
        screenResolver: @escaping (UInt32) -> NSScreen? = floatingIndicatorDefaultScreen(for:),
        mousePollingScheduler: @escaping @MainActor (@escaping @MainActor () -> Void) -> any FloatingIndicatorMousePollingSession = floatingIndicatorDefaultMousePollingScheduler(handler:)
    ) {
        self.contextEngineService = contextEngineService
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.now = now
        self.axObservationService = axObservationService ?? FloatingIndicatorAXObservationService(axProvider: axProvider)
        self.mouseDisplayNumberProvider = mouseDisplayNumberProvider
        self.displayNumberForRect = displayNumberForRect
        self.screenResolver = screenResolver
        self.mousePollingScheduler = mousePollingScheduler
        self.resources = FloatingIndicatorFocusTrackerResources(
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    deinit {
        // Nonisolated fallback: only the resource holder is touched.
        // Mouse/AX sessions release via ARC; their own deinit cleans framework resources.
        // Explicit `stop()` remains the primary MainActor teardown path.
        resources.tearDown()
    }

    var placementContext: FloatingIndicatorPlacementContext? {
        placementContextValue
    }

    func start(mode: FloatingIndicatorTrackingMode) {
        let isRestartingInNewMode = trackingMode != nil && trackingMode != mode
        trackingMode = mode

        if !resources.hasWorkspaceObserver {
            let token = workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleFrontmostApplicationActivated()
                }
            }
            resources.installWorkspaceObserver(token)
        }

        // Mouse display tracking is only needed for idle placement. During an
        // active session, AX/focus notifications own placement — stop the
        // pointer session so idle mouse work is fully paused.
        switch mode {
        case .idlePill:
            lastObservedMouseDisplayNumber = mouseDisplayNumberProvider()
            if mousePollingSession == nil {
                mousePollingSession = mousePollingScheduler { [weak self] in
                    self?.handleMouseTick()
                }
            }
        case .activeSession:
            lastObservedMouseDisplayNumber = nil
            mousePollingSession?.invalidate()
            mousePollingSession = nil
        }

        if axObservationSession == nil || isRestartingInNewMode {
            installAXObservation()
        }


        guard placementContextValue == nil else {
            if isRestartingInNewMode {
                seedPlacement(for: mode)
            }
            return
        }

        seedPlacement(for: mode)
    }

    func stop() {
        trackingMode = nil
        placementContextValue = nil
        lastObservedMouseDisplayNumber = nil

        mousePollingSession?.invalidate()
        mousePollingSession = nil

        axObservationSession?.invalidate()
        axObservationSession = nil

        // Primary MainActor teardown. Resource-holder tearDown is also invoked by
        // deinit; calling both is safe and keeps deinit a no-op afterward.
        resources.tearDown()
    }

    func preferredScreen() -> NSScreen? {
        if let placementContextValue,
           let screen = screenResolver(placementContextValue.displayNumber) {
            return screen
        }

        guard let displayNumber = mouseDisplayNumberProvider() else { return nil }
        return screenResolver(displayNumber)
    }

    func handleMouseTick() {
        guard trackingMode == .idlePill else { return }
        guard let displayNumber = mouseDisplayNumberProvider() else { return }

        defer { lastObservedMouseDisplayNumber = displayNumber }

        guard let lastObservedMouseDisplayNumber else {
            return
        }

        guard displayNumber != lastObservedMouseDisplayNumber else { return }
        applyPlacement(
            displayNumber: displayNumber,
            source: .mouse,
            updatedAt: now()
        )
    }

    private func seedPlacement(for mode: FloatingIndicatorTrackingMode) {
        let seededAt = now()

        switch mode {
        case .idlePill:
            guard let displayNumber = mouseDisplayNumberProvider() else { return }
            applyPlacement(displayNumber: displayNumber, source: .mouse, updatedAt: seededAt)

        case .activeSession:
            if let focusPlacement = resolveFocusPlacement(updatedAt: seededAt) {
                applyPlacement(focusPlacement)
            } else if placementContextValue == nil,
                      let fallbackDisplayNumber = mouseDisplayNumberProvider() {
                applyPlacement(displayNumber: fallbackDisplayNumber, source: .mouse, updatedAt: seededAt)
            }
        }
    }

    private func handleFrontmostApplicationActivated() {
        guard trackingMode != nil else { return }
        installAXObservation()
        handleFocusEvent(source: .frontmostApplication)
    }

    private func installAXObservation() {
        axObservationSession?.invalidate()
        axObservationSession = axObservationService.beginObservation { [weak self] event in
            switch event {
            case .focusedWindowChanged:
                self?.handleFocusEvent(source: .focusedWindow)
            case .focusedElementChanged:
                self?.handleFocusEvent(source: .focusedElement)
            }
        }
    }

    private func handleFocusEvent(source: FloatingIndicatorFocusSource) {
        let updatedAt = now()

        if let focusPlacement = resolveFocusPlacement(updatedAt: updatedAt, preferredSource: source) {
            applyPlacement(focusPlacement)
            return
        }

        guard placementContextValue == nil,
              let fallbackDisplayNumber = mouseDisplayNumberProvider() else {
            return
        }

        applyPlacement(displayNumber: fallbackDisplayNumber, source: source, updatedAt: updatedAt)
    }

    private func resolveFocusDisplayNumber() -> UInt32? {
        if let windowFrame = contextEngineService.captureFocusedWindowFrame(),
           let displayNumber = displayNumberForRect(windowFrame) {
            return displayNumber
        }

        if let anchorRect = contextEngineService.captureFocusedElementAnchorRect(),
           let displayNumber = displayNumberForRect(anchorRect) {
            return displayNumber
        }

        return nil
    }

    private func resolveFocusPlacement(
        updatedAt: Date,
        preferredSource: FloatingIndicatorFocusSource? = nil
    ) -> FloatingIndicatorPlacementContext? {
        if let windowFrame = contextEngineService.captureFocusedWindowFrame(),
           let displayNumber = displayNumberForRect(windowFrame) {
            return FloatingIndicatorPlacementContext(
                displayNumber: displayNumber,
                source: preferredSource ?? .focusedWindow,
                updatedAt: updatedAt
            )
        }

        if let anchorRect = contextEngineService.captureFocusedElementAnchorRect(),
           let displayNumber = displayNumberForRect(anchorRect) {
            return FloatingIndicatorPlacementContext(
                displayNumber: displayNumber,
                source: .focusedElement,
                updatedAt: updatedAt
            )
        }

        return nil
    }

    private func applyPlacement(
        _ candidate: FloatingIndicatorPlacementContext
    ) {
        applyPlacement(
            displayNumber: candidate.displayNumber,
            source: candidate.source,
            updatedAt: candidate.updatedAt
        )
    }

    private func applyPlacement(
        displayNumber: UInt32,
        source: FloatingIndicatorFocusSource,
        updatedAt: Date
    ) {
        guard displayNumber != 0 else { return }

        let candidate = FloatingIndicatorPlacementContext(
            displayNumber: displayNumber,
            source: source,
            updatedAt: updatedAt
        )

        guard shouldAccept(candidate) else { return }
        placementContextValue = candidate
    }

    private func shouldAccept(_ candidate: FloatingIndicatorPlacementContext) -> Bool {
        guard let current = placementContextValue else { return true }
        guard candidate.updatedAt >= current.updatedAt else { return false }

        if candidate.displayNumber != current.displayNumber {
            return true
        }

        return candidate.source != current.source
    }

}

extension Timer: FloatingIndicatorMousePollingSession {}

/// Event-driven replacement for 20 Hz mouse-display polling.
/// Fires the handler on real pointer motion or screen reconfiguration, already
/// on the main thread — no `Task { @MainActor }` hop per tick.
@MainActor
private final class FloatingIndicatorEventDrivenMouseSession: FloatingIndicatorMousePollingSession {
    private var pointerMonitor: FloatingIndicatorPointerMonitor?
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        let monitor = FloatingIndicatorPointerMonitor(
            onPointerActivity: { [weak self] in
                self?.handler()
            },
            onScreenParametersChanged: { [weak self] in
                self?.handler()
            }
        )
        self.pointerMonitor = monitor
        monitor.start()
        // Seed once so a display change that already occurred is observed.
        handler()
    }

    func invalidate() {
        pointerMonitor?.stop()
        pointerMonitor = nil
    }
}

@MainActor
private final class FloatingIndicatorAXObservationService: FloatingIndicatorAXObserving {
    private let axProvider: AXProviderProtocol

    init(axProvider: AXProviderProtocol) {
        self.axProvider = axProvider
    }

    func beginObservation(
        handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    ) -> (any FloatingIndicatorAXObservationSession)? {
        FloatingIndicatorAXObserverSession(axProvider: axProvider, handler: handler)
    }
}

// MARK: - Focus tracker resources (nonisolated for deinit)

/// Owns the workspace observer token so teardown can run from nonisolated
/// `deinit` without reading MainActor-isolated stored properties on
/// `FloatingIndicatorFocusTracker`.
private final class FloatingIndicatorFocusTrackerResources: @unchecked Sendable {
    private let lock = NSLock()
    private let workspaceNotificationCenter: NotificationCenter
    private var workspaceObserverToken: NSObjectProtocol?

    init(workspaceNotificationCenter: NotificationCenter) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    var hasWorkspaceObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return workspaceObserverToken != nil
    }

    /// Installs a new observer token, removing any previous one.
    func installWorkspaceObserver(_ token: NSObjectProtocol) {
        lock.lock()
        let previous = workspaceObserverToken
        workspaceObserverToken = token
        lock.unlock()
        if let previous {
            workspaceNotificationCenter.removeObserver(previous)
        }
    }

    /// Idempotent: removes the observer and clears the stored token.
    func tearDown() {
        lock.lock()
        let token = workspaceObserverToken
        workspaceObserverToken = nil
        lock.unlock()
        if let token {
            workspaceNotificationCenter.removeObserver(token)
        }
    }
}

// MARK: - AX observer resources (nonisolated for deinit)

/// Owns the AXObserver, registered notifications, and run-loop source so
/// teardown can run from nonisolated `deinit` without calling MainActor-isolated
/// `invalidate()`.
private final class FloatingIndicatorAXObserverResources: @unchecked Sendable {
    private let lock = NSLock()
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var registeredNotifications: [String] = []
    private var isInvalidated = false

    /// Immutable AX application element used for notification registration/removal.
    var appElementForRegistration: AXUIElement { appElement }

    init(appElement: AXUIElement, observer: AXObserver) {
        self.appElement = appElement
        self.observer = observer
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isInvalidated
    }

    func currentObserver() -> AXObserver? {
        lock.lock()
        defer { lock.unlock() }
        return observer
    }

    func addRegisteredNotification(_ notification: String) {
        lock.lock()
        registeredNotifications.append(notification)
        lock.unlock()
    }

    /// Idempotent: remove notifications, detach the run-loop source, clear observer.
    func tearDown() {
        lock.lock()
        let observer = self.observer
        let notifications = registeredNotifications
        let wasInvalidated = isInvalidated
        isInvalidated = true
        self.observer = nil
        registeredNotifications = []
        lock.unlock()

        guard !wasInvalidated, let observer else { return }

        for notification in notifications {
            AXObserverRemoveNotification(observer, appElement, notification as CFString)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }
}

private final class FloatingIndicatorAXObserverSession: FloatingIndicatorAXObservationSession {
    private let resources: FloatingIndicatorAXObserverResources
    private let handler: @MainActor (FloatingIndicatorAXObservationEvent) -> Void

    init?(
        axProvider: AXProviderProtocol,
        handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    ) {
        guard let appPID = axProvider.frontmostAppPID(),
              let appElement = axProvider.copyFrontmostApplication() else {
            return nil
        }

        self.handler = handler

        var createdObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let session = Unmanaged<FloatingIndicatorAXObserverSession>.fromOpaque(refcon).takeUnretainedValue()
            session.handleAXNotification(notification as String)
        }

        guard AXObserverCreate(appPID, callback, &createdObserver) == .success,
              let observer = createdObserver else {
            return nil
        }

        self.resources = FloatingIndicatorAXObserverResources(
            appElement: appElement,
            observer: observer
        )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        register(notification: kAXFocusedWindowChangedNotification as String)
        register(notification: kAXFocusedUIElementChangedNotification as String)
    }

    deinit {
        // Nonisolated fallback: only the resource holder is touched.
        // Explicit `invalidate()` remains the primary MainActor teardown path.
        resources.tearDown()
    }

    func invalidate() {
        resources.tearDown()
    }

    private func register(notification: String) {
        guard let observer = resources.currentObserver() else { return }

        let result = AXObserverAddNotification(
            observer,
            resources.appElementForRegistration,
            notification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard result == .success else { return }
        resources.addRegisteredNotification(notification)
    }

    private func handleAXNotification(_ notification: String) {
        guard resources.isActive else { return }

        let event: FloatingIndicatorAXObservationEvent
        switch notification {
        case kAXFocusedWindowChangedNotification:
            event = .focusedWindowChanged
        case kAXFocusedUIElementChangedNotification:
            event = .focusedElementChanged
        default:
            return
        }

        Task { @MainActor in
            self.handler(event)
        }
    }
}
