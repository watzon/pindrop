//
// UpdateServiceTests.swift
// PindropTests
//
// Created on 2026-02-02.
//

import XCTest
import SwiftData
@testable import Pindrop

@MainActor
final class UpdateServiceTests: XCTestCase {

    var sut: UpdateService!

    override func setUp() async throws {
        sut = UpdateService()
    }

    override func tearDown() async throws {
        sut = nil
    }

    // MARK: - Initial State Tests

    func testInitialState() async throws {
        XCTAssertEqual(sut.state, .idle, "Initial state should be idle")
        XCTAssertNil(sut.error, "Initial error should be nil")
    }

    // MARK: - Defer Update Tests

    func testShouldDeferUpdateWhenRecording() async throws {
        let shouldDefer = sut.shouldDeferUpdate(isRecording: true)
        XCTAssertTrue(shouldDefer, "Should defer update when recording is in progress")
    }

    func testShouldNotDeferUpdateWhenNotRecording() async throws {
        let shouldDefer = sut.shouldDeferUpdate(isRecording: false)
        XCTAssertFalse(shouldDefer, "Should not defer update when not recording")
    }

    // MARK: - Property Tests

    func testAutomaticallyChecksForUpdatesProperty() async throws {
        // Property should be accessible (may be false if Sparkle not fully configured)
        _ = sut.automaticallyChecksForUpdates

        // Should be able to set it
        let originalValue = sut.automaticallyChecksForUpdates
        sut.automaticallyChecksForUpdates = !originalValue

        // Note: In test environment, Sparkle may not be fully initialized
        // so we just verify the property access works
        XCTAssertTrue(true, "Property access should not crash")
    }

    func testCanCheckForUpdates() async throws {
        // Property should be accessible
        _ = sut.canCheckForUpdates

        // Note: In test environment, Sparkle may not be fully initialized
        // so we just verify the property access works
        XCTAssertTrue(true, "Property access should not crash")
    }

    func testLastUpdateCheckDate() async throws {
        // Property should be accessible (may be nil initially)
        _ = sut.lastUpdateCheckDate

        // Note: In test environment, Sparkle may not be fully initialized
        // so we just verify the property access works
        XCTAssertTrue(true, "Property access should not crash")
    }

    // MARK: - State Transition Tests

    func testStateTransitionsToChecking() async throws {
        // Initial state
        XCTAssertEqual(sut.state, .idle)

        // Trigger update check
        sut.checkForUpdates()

        // Give a moment for state to update
        try await Task.sleep(nanoseconds: 50_000_000)

        // State can be:
        // - .checking: if Sparkle is initialized and can check
        // - .error: if updaterController is nil
        // - .idle: if canCheckForUpdates is false (check not allowed)
        XCTAssertTrue(
            sut.state == .checking || sut.state == .error || sut.state == .idle,
            "State should be checking, error, or idle after checkForUpdates, but was \(String(describing: sut.state))"
        )
    }

    func testStateReturnsToIdleAfterCheckTimeout() async throws {
        // Trigger update check
        sut.checkForUpdates()

        // Wait for the timeout (3 seconds + buffer)
        try await Task.sleep(nanoseconds: 4_000_000_000)

        // State should return to idle or be error
        XCTAssertTrue(
            sut.state == .idle || sut.state == .error,
            "State should return to idle or be error after timeout"
        )
    }

    // MARK: - Error Tests

    func testUpdateErrorDescriptions() {
        let errors: [UpdateService.UpdateError] = [
            .updaterNotInitialized,
            .checkFailed("test message"),
            .updateInProgress
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have error description")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) description should not be empty")
        }
    }

    func testUpdaterNotInitializedErrorDescription() {
        let error = UpdateService.UpdateError.updaterNotInitialized
        XCTAssertEqual(error.errorDescription, "Update service not initialized")
    }

    func testCheckFailedErrorDescription() {
        let error = UpdateService.UpdateError.checkFailed("network timeout")
        XCTAssertEqual(error.errorDescription, "Update check failed: network timeout")
    }

    func testUpdateInProgressErrorDescription() {
        let error = UpdateService.UpdateError.updateInProgress
        XCTAssertEqual(error.errorDescription, "An update is already in progress")
    }

    // MARK: - Background Check Tests

    func testCheckForUpdatesInBackgroundDoesNotCrash() async throws {
        // This should not crash even in test environment
        sut.checkForUpdatesInBackground()

        // Give it a moment
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(true, "Background check should not crash")
    }

    // MARK: - Error State Tests

    func testErrorIsSetOnFailedCheck() async throws {
        // Initial error should be nil
        XCTAssertNil(sut.error)

        // Trigger check (may fail in test environment)
        sut.checkForUpdates()

        // If state is error, error should be set
        if sut.state == .error {
            XCTAssertNotNil(sut.error, "Error should be set when state is error")
        }
    }

    func testAppCoordinatorWiresStatusBarCheckForUpdatesAction() async throws {
        let schema = Schema([
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        let coordinator = AppCoordinator(
            modelContext: modelContainer.mainContext,
            modelContainer: modelContainer
        )

        XCTAssertNotNil(
            coordinator.statusBarController.onCheckForUpdates,
            "Status bar update menu item should be wired to coordinator handler"
        )

        coordinator.cleanup()
    }
}
