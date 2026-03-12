//
//  ToastServiceTests.swift
//  PindropTests
//
//  Created on 2026-03-11.
//

import XCTest
@testable import Pindrop

@MainActor
private final class MockToastPresenter: ToastPresenting {
    private(set) var shownPayloads: [ToastPayload] = []
    private(set) var hideCallCount = 0
    private(set) var currentActionHandler: ((UUID) -> Void)?

    func show(payload: ToastPayload, onAction: @escaping (UUID) -> Void) {
        shownPayloads.append(payload)
        currentActionHandler = onAction
    }

    func hide() {
        hideCallCount += 1
        currentActionHandler = nil
    }
}

@MainActor
final class ToastServiceTests: XCTestCase {
    private var presenter: MockToastPresenter!
    private var toastService: ToastService!

    override func setUp() async throws {
        presenter = MockToastPresenter()
        toastService = ToastService(presenter: presenter)
    }

    override func tearDown() async throws {
        toastService = nil
        presenter = nil
    }

    func testShowToastWithMessageOnly() {
        toastService.show(ToastPayload(message: "Saved", duration: nil))

        XCTAssertEqual(presenter.shownPayloads.count, 1)
        XCTAssertEqual(presenter.shownPayloads.first?.message, "Saved")
        XCTAssertTrue(presenter.shownPayloads.first?.actions.isEmpty == true)
    }

    func testShowToastWithTwoActions() {
        toastService.show(
            ToastPayload(
                message: "Added to dictionary",
                actions: [
                    ToastAction(title: "Undo", role: .primary) {},
                    ToastAction(title: "Dismiss", role: .secondary) {}
                ],
                duration: nil
            )
        )

        XCTAssertEqual(presenter.shownPayloads.count, 1)
        XCTAssertEqual(presenter.shownPayloads.first?.actions.count, 2)
    }

    func testQueueingMultipleToastsPresentsInOrder() {
        toastService.show(ToastPayload(message: "First", duration: nil))
        toastService.show(ToastPayload(message: "Second", duration: nil))

        XCTAssertEqual(presenter.shownPayloads.count, 1)
        XCTAssertEqual(presenter.shownPayloads.last?.message, "First")

        toastService.dismissCurrentToast()

        XCTAssertEqual(presenter.shownPayloads.count, 2)
        XCTAssertEqual(presenter.shownPayloads.last?.message, "Second")
    }

    func testDuplicateVisibleToastRefreshesInsteadOfQueueing() {
        let first = ToastPayload(message: "Added", duration: nil)
        let duplicate = ToastPayload(message: "Added", duration: nil)

        toastService.show(first)
        toastService.show(duplicate)

        XCTAssertEqual(presenter.shownPayloads.count, 2)
        toastService.dismissCurrentToast()

        XCTAssertEqual(presenter.shownPayloads.last?.message, "Added")
        XCTAssertEqual(presenter.hideCallCount, 1)
    }

    func testActionTapInvokesHandlerAndDismissesToast() {
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

        toastService.show(payload)
        presenter.currentActionHandler?(payload.actions[0].id)

        XCTAssertTrue(actionTriggered)
        XCTAssertEqual(presenter.hideCallCount, 1)
    }
}
