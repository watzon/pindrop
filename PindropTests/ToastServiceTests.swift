//
//  ToastServiceTests.swift
//  PindropTests
//
//  Created on 2026-03-21.
//

import Foundation
import Testing
@testable import Pindrop

@MainActor
private final class MockToastPresenter: ToastPresenting {
    private(set) var shownPayloads: [ToastPayload] = []
    private(set) var hideCallCount = 0
    private(set) var currentActionHandler: ((UUID) -> Void)?
    private(set) var currentHoverHandler: ((Bool) -> Void)?

    func show(
        payload: ToastPayload,
        onAction: @escaping (UUID) -> Void,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        shownPayloads.append(payload)
        currentActionHandler = onAction
        currentHoverHandler = onHoverChange
    }

    func hide() {
        hideCallCount += 1
        currentActionHandler = nil
        currentHoverHandler = nil
    }
}

@MainActor
@Suite(.serialized)
struct ToastServiceTests {
    @Test func showsMessageOnlyToast() {
        let presenter = MockToastPresenter()
        let scheduler = ManualTaskScheduler()
        let service = ToastService(presenter: presenter, scheduler: scheduler)

        service.show(ToastPayload(message: "Saved", duration: nil))

        #expect(presenter.shownPayloads.count == 1)
        #expect(presenter.shownPayloads.first?.message == "Saved")
        #expect(presenter.shownPayloads.first?.actions.isEmpty == true)
    }

    @Test func queuesMultipleToastsInOrder() {
        let presenter = MockToastPresenter()
        let scheduler = ManualTaskScheduler()
        let service = ToastService(presenter: presenter, scheduler: scheduler)

        service.show(ToastPayload(message: "First", duration: nil))
        service.show(ToastPayload(message: "Second", duration: nil))

        #expect(presenter.shownPayloads.count == 1)
        #expect(presenter.shownPayloads.last?.message == "First")

        service.dismissCurrentToast()

        #expect(presenter.shownPayloads.count == 2)
        #expect(presenter.shownPayloads.last?.message == "Second")
    }

    @Test func duplicateVisibleToastRefreshesInsteadOfQueueing() {
        let presenter = MockToastPresenter()
        let scheduler = ManualTaskScheduler()
        let service = ToastService(presenter: presenter, scheduler: scheduler)

        let first = ToastPayload(message: "Added", duration: nil)
        let duplicate = ToastPayload(message: "Added", duration: nil)

        service.show(first)
        service.show(duplicate)

        #expect(presenter.shownPayloads.count == 2)

        service.dismissCurrentToast()

        #expect(presenter.shownPayloads.last?.message == "Added")
        #expect(presenter.hideCallCount == 1)
    }

    @Test func actionTapInvokesHandlerAndDismissesToast() {
        let presenter = MockToastPresenter()
        let scheduler = ManualTaskScheduler()
        let service = ToastService(presenter: presenter, scheduler: scheduler)
        var actionTriggered = false
        let payload = ToastPayload(
            message: "Added",
            actions: [
                ToastAction(title: "Undo", role: .primary) {
                    actionTriggered = true
                }
            ],
            duration: nil
        )

        service.show(payload)
        presenter.currentActionHandler?(payload.actions[0].id)

        #expect(actionTriggered)
        #expect(presenter.hideCallCount == 1)
    }

    @Test func hoverPausesAndResumesAutoDismissWithoutSleeping() {
        let presenter = MockToastPresenter()
        let scheduler = ManualTaskScheduler(now: Date(timeIntervalSince1970: 1_000))
        let service = ToastService(presenter: presenter, scheduler: scheduler)

        service.show(ToastPayload(message: "Saved", duration: 0.25))

        scheduler.advance(by: 0.08)
        presenter.currentHoverHandler?(true)

        scheduler.advance(by: 0.25)
        #expect(presenter.hideCallCount == 0)

        presenter.currentHoverHandler?(false)

        scheduler.advance(by: 0.08)
        #expect(presenter.hideCallCount == 0)

        scheduler.advance(by: 0.17)
        #expect(presenter.hideCallCount == 1)
    }
}
