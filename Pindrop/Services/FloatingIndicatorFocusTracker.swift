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
    Timer.pindrop_scheduleRepeating(interval: 0.05) { _ in
        Task { @MainActor in
            handler()
        }
    }
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
    private let mousePollingScheduler: (@escaping @MainActor () -> Void) -> any FloatingIndicatorMousePollingSession

    private var trackingMode: FloatingIndicatorTrackingMode?
    private var placementContextValue: FloatingIndicatorPlacementContext?
    private var mousePollingSession: (any FloatingIndicatorMousePollingSession)?
    private var workspaceObserverToken: NSObjectProtocol?
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
        mousePollingScheduler: @escaping (@escaping @MainActor () -> Void) -> any FloatingIndicatorMousePollingSession = floatingIndicatorDefaultMousePollingScheduler(handler:)
    ) {
        self.contextEngineService = contextEngineService
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.now = now
        self.axObservationService = axObservationService ?? FloatingIndicatorAXObservationService(axProvider: axProvider)
        self.mouseDisplayNumberProvider = mouseDisplayNumberProvider
        self.displayNumberForRect = displayNumberForRect
        self.screenResolver = screenResolver
        self.mousePollingScheduler = mousePollingScheduler
    }

    var placementContext: FloatingIndicatorPlacementContext? {
        placementContextValue
    }

    func start(mode: FloatingIndicatorTrackingMode) {
        let isRestartingInNewMode = trackingMode != nil && trackingMode != mode
        trackingMode = mode

        if workspaceObserverToken == nil {
            workspaceObserverToken = workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleFrontmostApplicationActivated()
                }
            }
        }

        if mousePollingSession == nil {
            mousePollingSession = mousePollingScheduler { [weak self] in
                self?.handleMouseTick()
            }
        }

        if axObservationSession == nil || isRestartingInNewMode {
            installAXObservation()
        }

        lastObservedMouseDisplayNumber = mouseDisplayNumberProvider()

        guard placementContextValue == nil else {
            if isRestartingInNewMode, mode == .idlePill {
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

        if let workspaceObserverToken {
            workspaceNotificationCenter.removeObserver(workspaceObserverToken)
            self.workspaceObserverToken = nil
        }
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
        guard trackingMode != nil else { return }
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

private final class FloatingIndicatorAXObserverSession: FloatingIndicatorAXObservationSession {
    private let appElement: AXUIElement
    private let handler: @MainActor (FloatingIndicatorAXObservationEvent) -> Void

    private var observer: AXObserver?
    private var registeredNotifications: [String] = []
    private var isInvalidated = false

    init?(
        axProvider: AXProviderProtocol,
        handler: @escaping @MainActor (FloatingIndicatorAXObservationEvent) -> Void
    ) {
        guard let appPID = axProvider.frontmostAppPID(),
              let appElement = axProvider.copyFrontmostApplication() else {
            return nil
        }

        self.appElement = appElement
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

        self.observer = observer

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        register(notification: kAXFocusedWindowChangedNotification as String)
        register(notification: kAXFocusedUIElementChangedNotification as String)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        if let observer {
            for notification in registeredNotifications {
                AXObserverRemoveNotification(observer, appElement, notification as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        registeredNotifications.removeAll()
        observer = nil
    }

    private func register(notification: String) {
        guard let observer else { return }

        let result = AXObserverAddNotification(
            observer,
            appElement,
            notification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard result == .success else { return }
        registeredNotifications.append(notification)
    }

    private func handleAXNotification(_ notification: String) {
        guard !isInvalidated else { return }

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
