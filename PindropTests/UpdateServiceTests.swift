//
//  UpdateServiceTests.swift
//  PindropTests
//
//  Created on 2026-03-21.
//

import Foundation
import SwiftData
import Testing
@testable import Pindrop

@MainActor
private final class MockUpdateController: UpdateControlling {
    var automaticallyChecksForUpdates = false
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    private(set) var checkForUpdatesCallCount = 0
    private(set) var backgroundCheckCallCount = 0

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }

    func checkForUpdatesInBackground() {
        backgroundCheckCallCount += 1
    }
}

@MainActor
@Suite(.serialized)
struct UpdateServiceTests {
    @Test func startsIdle() {
        let service = UpdateService(updateController: MockUpdateController(), timeoutScheduler: ManualTaskScheduler())

        #expect(service.state == .idle)
        #expect(service.error == nil)
    }

    @Test func defersUpdateWhileRecording() {
        let service = UpdateService(updateController: MockUpdateController(), timeoutScheduler: ManualTaskScheduler())

        #expect(service.shouldDeferUpdate(isRecording: true))
        #expect(service.shouldDeferUpdate(isRecording: false) == false)
    }

    @Test func exposesControllerBackedProperties() {
        let controller = MockUpdateController()
        controller.automaticallyChecksForUpdates = false
        controller.lastUpdateCheckDate = Date(timeIntervalSince1970: 321)
        let service = UpdateService(updateController: controller, timeoutScheduler: ManualTaskScheduler())

        #expect(service.automaticallyChecksForUpdates == false)
        service.automaticallyChecksForUpdates = true
        #expect(controller.automaticallyChecksForUpdates)
        #expect(service.canCheckForUpdates)
        #expect(service.lastUpdateCheckDate == controller.lastUpdateCheckDate)
    }

    @Test func checkForUpdatesTransitionsToCheckingAndBackToIdleOnTimeout() {
        let controller = MockUpdateController()
        let scheduler = ManualTaskScheduler(now: Date(timeIntervalSince1970: 500))
        let service = UpdateService(
            updateController: controller,
            timeoutScheduler: scheduler,
            checkTimeout: 3.0
        )

        service.checkForUpdates()

        #expect(service.state == .checking)
        #expect(controller.checkForUpdatesCallCount == 1)

        scheduler.advance(by: 2.9)
        #expect(service.state == .checking)

        scheduler.advance(by: 0.11)
        #expect(service.state == .idle)
    }

    @Test func checkForUpdatesRecordsTypedErrorWithoutController() throws {
        let service = UpdateService(updateController: nil, timeoutScheduler: ManualTaskScheduler())

        service.checkForUpdates()

        #expect(service.state == .error)
        let error = try #require(service.error as? UpdateService.UpdateError)
        if case .updaterNotInitialized = error {
            #expect(Bool(true))
        } else {
            Issue.record("Expected updaterNotInitialized but received \(error.localizedDescription)")
        }
    }

    @Test func checkForUpdatesDoesNothingWhenControllerCannotCheck() {
        let controller = MockUpdateController()
        controller.canCheckForUpdates = false
        let service = UpdateService(updateController: controller, timeoutScheduler: ManualTaskScheduler())

        service.checkForUpdates()

        #expect(service.state == .idle)
        #expect(controller.checkForUpdatesCallCount == 0)
    }

    @Test func backgroundCheckUsesControllerWithoutSleep() {
        let controller = MockUpdateController()
        let service = UpdateService(updateController: controller, timeoutScheduler: ManualTaskScheduler())

        service.checkForUpdatesInBackground()

        #expect(controller.backgroundCheckCallCount == 1)
    }

    @Test func updateErrorsProvideDescriptions() {
        let errors: [UpdateService.UpdateError] = [
            .updaterNotInitialized,
            .checkFailed("network timeout"),
            .updateInProgress,
        ]

        #expect(errors[0].errorDescription == "Update service not initialized")
        #expect(errors[1].errorDescription == "Update check failed: network timeout")
        #expect(errors[2].errorDescription == "An update is already in progress")
    }

    @Test func appCoordinatorWiresCheckForUpdatesAction() throws {
        let schema = Schema([
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        let coordinator = AppCoordinator(
            modelContext: modelContainer.mainContext,
            modelContainer: modelContainer
        )

        #expect(coordinator.statusBarController.onCheckForUpdates != nil)

        coordinator.cleanup()
    }
}
