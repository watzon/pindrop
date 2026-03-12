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
    let placement: ToastPlacement
    let screenHintRect: CGRect?

    init(
        id: UUID = UUID(),
        message: String,
        actions: [ToastAction] = [],
        duration: TimeInterval? = 4.0,
        placement: ToastPlacement = .bottomCenter,
        screenHintRect: CGRect? = nil
    ) {
        self.id = id
        self.message = message
        self.actions = Array(actions.prefix(2))
        self.duration = duration
        self.placement = placement
        self.screenHintRect = screenHintRect
    }
}

@MainActor
protocol ToastPresenting: AnyObject {
    func show(payload: ToastPayload, onAction: @escaping (UUID) -> Void)
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
    }

    private let presenter: ToastPresenting
    private var queue: [ToastPayload] = []
    private var activeToast: ActiveToast?
    private var dismissTask: Task<Void, Never>?

    init(presenter: ToastPresenting) {
        self.presenter = presenter
    }

    func show(_ payload: ToastPayload) {
        if let activeToast, activeToast.payload.signature == payload.signature {
            self.activeToast = ActiveToast(payload: payload)
            presenter.show(payload: payload, onAction: { [weak self] actionID in
                self?.handleActionSelection(id: actionID)
            })
            scheduleDismiss(for: payload)
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

    private func presentNextToastIfPossible() {
        guard activeToast == nil, !queue.isEmpty else { return }
        let nextToast = queue.removeFirst()
        activeToast = ActiveToast(payload: nextToast)
        presenter.show(payload: nextToast, onAction: { [weak self] actionID in
            self?.handleActionSelection(id: actionID)
        })
        scheduleDismiss(for: nextToast)
    }

    private func scheduleDismiss(for payload: ToastPayload) {
        dismissTask?.cancel()
        guard let duration = payload.duration, duration > 0 else {
            dismissTask = nil
            return
        }

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissCurrentToast()
        }
    }
}

private extension ToastPayload {
    var signature: String {
        let actionSignature = actions.map { "\($0.title)|\($0.role)" }.joined(separator: "|")
        return "\(message)|\(placement)|\(actionSignature)"
    }
}
