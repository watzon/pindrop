//
//  ToastService.swift
//  Pindrop
//
//  Created on 2026-03-11.
//

import CoreGraphics
import Foundation
import Observation

enum ToastPlacement: Equatable {
    case bottomCenter
    case bottomTrailing
}

enum ToastStyle: Equatable {
    case standard
    case error
}

enum ToastVariant: Equatable {
    case standard
    case inserted(wordCount: Int)
    case copied
    case microphoneUnavailable
}

enum ToastVariantPresentation {
    static func trailingText(for variant: ToastVariant, locale: Locale) -> String? {
        guard case .inserted(let wordCount) = variant else { return nil }
        return String(format: localized("%d words", locale: locale), locale: locale, wordCount)
    }

    static func systemImage(for variant: ToastVariant, style: ToastStyle) -> String {
        switch variant {
        case .inserted:
            return "checkmark"
        case .copied:
            return "doc.on.doc"
        case .microphoneUnavailable:
            return "exclamationmark.triangle"
        case .standard:
            return style == .error ? "exclamationmark.triangle" : "checkmark"
        }
    }
}

enum ToastActionRole: Equatable {
    case primary
    case secondary
}

struct ToastAction {
    let id: UUID
    let title: String
    let role: ToastActionRole
    let handler: @MainActor () -> Void

    init(
        id: UUID = UUID(),
        title: String,
        role: ToastActionRole = .secondary,
        handler: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.handler = handler
    }
}

struct ToastPayload {
    let id: UUID
    let message: String
    let actions: [ToastAction]
    let duration: TimeInterval?
    let style: ToastStyle
    let variant: ToastVariant
    let placement: ToastPlacement
    let screenHintRect: CGRect?

    init(
        id: UUID = UUID(),
        message: String,
        actions: [ToastAction] = [],
        duration: TimeInterval? = 4.0,
        style: ToastStyle = .standard,
        variant: ToastVariant = .standard,
        placement: ToastPlacement = .bottomTrailing,
        screenHintRect: CGRect? = nil
    ) {
        self.id = id
        self.message = message
        self.actions = Array(actions.prefix(2))
        self.duration = duration
        self.style = style
        self.variant = variant
        self.placement = placement
        self.screenHintRect = screenHintRect
    }
}

@MainActor
protocol ToastPresenting: AnyObject {
    func show(
        payload: ToastPayload,
        onAction: @escaping (UUID) -> Void,
        onHoverChange: @escaping (Bool) -> Void
    )
    func hide()
}

@MainActor
protocol ToastShowing: AnyObject {
    func show(_ payload: ToastPayload)
}

@MainActor
@Observable
final class ToastService: ToastShowing {
    private struct ActiveToast {
        var payload: ToastPayload
        var remainingDuration: TimeInterval?
        var dismissStartedAt: Date?
        var isTimerPaused = false

        init(payload: ToastPayload) {
            self.payload = payload
            self.remainingDuration = payload.duration
        }
    }

    private let presenter: ToastPresenting
    private let scheduler: TaskScheduling
    private var queue: [ToastPayload] = []
    private var activeToast: ActiveToast?
    private var dismissTask: ScheduledTask?

    init(presenter: ToastPresenting, scheduler: TaskScheduling = DefaultTaskScheduler()) {
        self.presenter = presenter
        self.scheduler = scheduler
    }

    func show(_ payload: ToastPayload) {
        if let activeToast, activeToast.payload.signature == payload.signature {
            self.activeToast = ActiveToast(payload: payload)
            presenter.show(
                payload: payload,
                onAction: { [weak self] actionID in
                    self?.handleActionSelection(id: actionID)
                },
                onHoverChange: { [weak self] isHovering in
                    self?.setTimerPaused(isHovering)
                }
            )
            scheduleDismiss(for: payload.duration)
            return
        }

        queue.append(payload)
        presentNextToastIfPossible()
    }

    func dismissCurrentToast() {
        dismissTask?.cancel()
        dismissTask = nil
        guard activeToast != nil else { return }
        activeToast = nil
        presenter.hide()
        presentNextToastIfPossible()
    }

    func handleActionSelection(id: UUID) {
        guard let activeToast else { return }
        guard let action = activeToast.payload.actions.first(where: { $0.id == id }) else { return }
        action.handler()
        dismissCurrentToast()
    }

    func pauseAutoDismiss() {
        setTimerPaused(true)
    }

    func resumeAutoDismiss() {
        setTimerPaused(false)
    }

    private func presentNextToastIfPossible() {
        guard activeToast == nil, !queue.isEmpty else { return }
        let nextToast = queue.removeFirst()
        activeToast = ActiveToast(payload: nextToast)
        presenter.show(
            payload: nextToast,
            onAction: { [weak self] actionID in
                self?.handleActionSelection(id: actionID)
            },
            onHoverChange: { [weak self] isHovering in
                self?.setTimerPaused(isHovering)
            }
        )
        scheduleDismiss(for: nextToast.duration)
    }

    private func scheduleDismiss(for remainingDuration: TimeInterval?) {
        dismissTask?.cancel()
        guard var activeToast else {
            dismissTask = nil
            return
        }

        guard let remainingDuration, remainingDuration > 0 else {
            activeToast.remainingDuration = remainingDuration
            activeToast.dismissStartedAt = nil
            activeToast.isTimerPaused = false
            self.activeToast = activeToast
            dismissTask = nil
            return
        }

        activeToast.remainingDuration = remainingDuration
        activeToast.dismissStartedAt = scheduler.now
        activeToast.isTimerPaused = false
        self.activeToast = activeToast

        dismissTask = scheduler.schedule(after: remainingDuration) { [weak self] in
            self?.dismissCurrentToast()
        }
    }

    private func setTimerPaused(_ isPaused: Bool) {
        guard var activeToast else { return }
        guard activeToast.isTimerPaused != isPaused else { return }
        guard let remainingDuration = activeToast.remainingDuration else { return }

        if isPaused {
            dismissTask?.cancel()
            dismissTask = nil

            if let dismissStartedAt = activeToast.dismissStartedAt {
                let elapsed = scheduler.now.timeIntervalSince(dismissStartedAt)
                activeToast.remainingDuration = max(0, remainingDuration - elapsed)
            }

            activeToast.dismissStartedAt = nil
            activeToast.isTimerPaused = true
            self.activeToast = activeToast
            return
        }

        activeToast.isTimerPaused = false
        self.activeToast = activeToast

        guard let resumedDuration = activeToast.remainingDuration, resumedDuration > 0 else {
            dismissCurrentToast()
            return
        }

        scheduleDismiss(for: resumedDuration)
    }
}

private extension ToastPayload {
    var signature: String {
        let actionSignature = actions.map { "\($0.title)|\($0.role)" }.joined(separator: "|")
        return "\(message)|\(style)|\(variant)|\(placement)|\(actionSignature)"
    }
}
